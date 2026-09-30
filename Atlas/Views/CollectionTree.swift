import AtlasCore
import SwiftUI

/// Where a dragged folder should land.
struct CollectionDrop {
    let draggedID: String
    let parentID: String?
    /// nil means "inside this folder"; a value means a position among siblings.
    let index: Int?
}

/// The folder tree.
///
/// Rows are hairline-separated rather than boxed, and indentation plus a left
/// accent carries the nesting. Reordering uses overlay strips on the top and
/// bottom edges of each row: they take no layout space, so the list stays tight,
/// but they are a real 10pt target rather than the 1pt line an earlier version
/// shrank to — which made dragging technically implemented and practically
/// impossible.
struct CollectionTreeRows: View {
    let nodes: [AtlasCollectionNode]
    let parentID: String?
    let selectedID: String?
    let expanded: Set<String>
    let directCount: (String) -> Int
    let totalCount: (String) -> Int
    let onSelect: (AtlasCollectionSnapshot) -> Void
    let onToggle: (String) -> Void
    let onAddChild: (AtlasCollectionSnapshot) -> Void
    let onEdit: (AtlasCollectionSnapshot) -> Void
    let onDrop: (CollectionDrop) -> Void

    var body: some View {
        ForEach(Array(nodes.enumerated()), id: \.element.id) { position, node in
            CollectionTreeRow(
                node: node,
                canMoveUp: position > 0,
                canMoveDown: position < nodes.count - 1,
                onMoveUp: { onDrop(CollectionDrop(draggedID: node.id, parentID: parentID, index: position - 1)) },
                onMoveDown: { onDrop(CollectionDrop(draggedID: node.id, parentID: parentID, index: position + 2)) },
                onMoveToTop: { onDrop(CollectionDrop(draggedID: node.id, parentID: nil, index: 0)) },
                isSelected: selectedID == node.id,
                isExpanded: expanded.contains(node.id),
                directCount: directCount(node.id),
                totalCount: totalCount(node.id),
                onSelect: { onSelect(node.collection) },
                onToggle: { onToggle(node.id) },
                onAddChild: { onAddChild(node.collection) },
                onEdit: { onEdit(node.collection) },
                onDropInside: { onDrop(CollectionDrop(draggedID: $0, parentID: node.id, index: nil)) },
                onDropBefore: { onDrop(CollectionDrop(draggedID: $0, parentID: parentID, index: position)) },
                onDropAfter: { onDrop(CollectionDrop(draggedID: $0, parentID: parentID, index: position + 1)) }
            )

            if expanded.contains(node.id), !node.children.isEmpty {
                CollectionTreeRows(
                    nodes: node.children,
                    parentID: node.id,
                    selectedID: selectedID,
                    expanded: expanded,
                    directCount: directCount,
                    totalCount: totalCount,
                    onSelect: onSelect,
                    onToggle: onToggle,
                    onAddChild: onAddChild,
                    onEdit: onEdit,
                    onDrop: onDrop
                )
            }
        }
    }
}

private struct CollectionTreeRow: View {
    let node: AtlasCollectionNode
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToTop: () -> Void
    let isSelected: Bool
    let isExpanded: Bool
    let directCount: Int
    let totalCount: Int
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onAddChild: () -> Void
    let onEdit: () -> Void
    let onDropInside: (String) -> Void
    let onDropBefore: (String) -> Void
    let onDropAfter: (String) -> Void

    @State private var isInsideTargeted = false
    @State private var isBeforeTargeted = false
    @State private var isAfterTargeted = false
    @State private var hovering = false
    @Environment(\.atlasPalette) private var theme

    private var accent: Color { theme.collectionColor(node.collection.accent) }
    private var hasChildren: Bool { !node.children.isEmpty }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(node.depth) * 16, height: 1)

            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .black))
                    .foregroundStyle(theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 15, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hasChildren ? 1 : 0)
            .disabled(!hasChildren)
            .accessibilityLabel(isExpanded ? "Collapse \(node.collection.title)" : "Expand \(node.collection.title)")

            Button(action: onSelect) { label }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .draggable(node.id) {
                    Text(node.collection.title)
                        .font(AtlasType.mono(10, .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(theme.surfaceRaised, in: Capsule())
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first, dragged != node.id else { return false }
                    onDropInside(dragged)
                    return true
                } isTargeted: { isInsideTargeted = $0 }
                // Edge strips sit on top of the row, so they cost no height
                // but still give a real target and live feedback.
                .overlay(alignment: .top) {
                    dropEdge(isTargeted: $isBeforeTargeted, onDrop: onDropBefore)
                }
                .overlay(alignment: .bottom) {
                    dropEdge(isTargeted: $isAfterTargeted, onDrop: onDropAfter)
                }
                .contextMenu {
                    // Keyboard-free reordering that does not depend on a drag
                    // session starting, which is worth having whatever the
                    // pointer does.
                    Button("Move up", action: onMoveUp).disabled(!canMoveUp)
                    Button("Move down", action: onMoveDown).disabled(!canMoveDown)
                    if node.depth > 0 {
                        Button("Move to top level", action: onMoveToTop)
                    }
                    Divider()
                    Button("New folder inside", action: onAddChild)
                    Button("Folder settings…", action: onEdit)
                }
        }
    }

    private var label: some View {
        HStack(spacing: 9) {
            // Full colour at every state; height carries the hierarchy.
            Capsule()
                .fill(accent)
                .frame(width: isSelected ? 3.5 : 2.5, height: isSelected ? 24 : (hovering ? 19 : 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(node.collection.title)
                    .font(AtlasType.body(14.5, isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textPrimary.opacity(0.82))
                    .lineLimit(1)
                Text(countLabel)
                    .font(AtlasType.mono(10))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.vertical, 9)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(alignment: .leading) {
            // A wash, not a card: it tints the row without drawing a border
            // around it.
            if isInsideTargeted {
                accent.opacity(0.24)
            } else if isSelected {
                LinearGradient(
                    colors: [accent.opacity(0.20), accent.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .animation(.easeOut(duration: 0.12), value: isInsideTargeted)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func dropEdge(isTargeted: Binding<Bool>, onDrop: @escaping (String) -> Void) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 10)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(theme.primary)
                    .frame(height: 2)
                    .opacity(isTargeted.wrappedValue ? 1 : 0)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first, dragged != node.id else { return false }
                onDrop(dragged)
                return true
            } isTargeted: { isTargeted.wrappedValue = $0 }
    }

    /// A parent reports what is under it as well as what is directly in it, so
    /// a folder used purely for grouping does not read as empty.
    private var countLabel: String {
        let direct = "\(directCount) note\(directCount == 1 ? "" : "s")"
        guard hasChildren else { return direct }
        let nested = totalCount - directCount
        let folders = "\(node.children.count) folder\(node.children.count == 1 ? "" : "s")"
        guard nested > 0 else { return "\(direct) · \(folders)" }
        return "\(direct) · \(folders) · \(nested) nested"
    }
}
