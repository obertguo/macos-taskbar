// Sources/TaskbarCore/Logic/WindowOrderingLogic.swift

import Foundation

/// Pure business logic for managing custom taskbar item ordering, slot reordering,
/// and order dictionary synchronization.
public enum WindowOrderingLogic {
    /// Applies a custom order dictionary to a list of `WindowGroup` items.
    ///
    /// Items present in `customOrder` are sorted by their assigned integer slot.
    /// Items not yet in `customOrder` (e.g. newly launched applications or windows)
    /// append after ordered items, preserving their natural discovery order.
    ///
    /// - Parameters:
    ///   - items: The input list of window groups.
    ///   - customOrder: A mapping from `WindowGroup.id` to its user-assigned slot index.
    /// - Returns: The re-ordered list of window groups.
    public static func applyCustomOrder(
        items: [WindowGroup],
        customOrder: [String: Int]
    ) -> [WindowGroup] {
        guard !items.isEmpty, !customOrder.isEmpty else { return items }
        
        return items.enumerated().sorted { (left, right) -> Bool in
            let leftSlot = customOrder[left.element.id] ?? left.element.windows.compactMap {
                customOrder[TaskbarConstants.Identifiers.windowID(pid: $0.key.pid, id: $0.key.id)]
            }.min()
            let rightSlot = customOrder[right.element.id] ?? right.element.windows.compactMap {
                customOrder[TaskbarConstants.Identifiers.windowID(pid: $0.key.pid, id: $0.key.id)]
            }.min()
            
            switch (leftSlot, rightSlot) {
            case let (l?, r?):
                if l != r {
                    return l < r
                }
                // Tie-breaker: original discovery index
                return left.offset < right.offset
            case (.some, .none):
                // Explicitly ordered items precede unordered items
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.offset < right.offset
            }
        }.map { $0.element }
    }
    
    /// Moves an item within an array of `WindowGroup` from `fromIndex` to `toIndex`,
    /// returning both the re-ordered array and the updated custom order dictionary.
    ///
    /// - Parameters:
    ///   - items: The array of window groups.
    ///   - fromIndex: The source index of the item being dragged.
    ///   - toIndex: The destination index where the item was dropped.
    /// - Returns: A tuple containing the updated array and the new `[String: Int]` order map.
    public static func moveItem(
        in items: [WindowGroup],
        fromIndex: Int,
        toIndex: Int
    ) -> (reordered: [WindowGroup], newOrder: [String: Int]) {
        guard fromIndex >= 0, fromIndex < items.count,
              toIndex >= 0, toIndex < items.count,
              fromIndex != toIndex else {
            return (items, rebuildOrderMap(for: items))
        }
        
        var mutableItems = items
        let moved = mutableItems.remove(at: fromIndex)
        mutableItems.insert(moved, at: toIndex)
        
        let newOrder = rebuildOrderMap(for: mutableItems)
        return (mutableItems, newOrder)
    }
    
    /// Generates a complete `[String: Int]` slot map for the given array of window groups.
    public static func rebuildOrderMap(for items: [WindowGroup]) -> [String: Int] {
        var map: [String: Int] = [:]
        map.reserveCapacity(items.count * 2)
        for (index, item) in items.enumerated() {
            map[item.id] = index
            for win in item.windows {
                let winKey = TaskbarConstants.Identifiers.windowID(pid: win.key.pid, id: win.key.id)
                map[winKey] = index
            }
        }
        return map
    }
    
    /// Prunes stale IDs from an existing order map that no longer exist among active groups.
    public static func pruneOrderMap(
        _ order: [String: Int],
        activeIDs: Set<String>
    ) -> [String: Int] {
        order.filter { activeIDs.contains($0.key) }
    }
}
