// Sources/TaskbarCore/Logic/WindowOrderingLogic.swift

import Foundation

/// Pure business logic for managing custom taskbar item ordering, slot reordering,
/// and order dictionary synchronization.
public enum WindowOrderingLogic {
    /// Applies a custom order dictionary to a list of `WindowGroup` items using a single-pass
    /// Decorate-Sort-Undecorate algorithm.
    ///
    /// Items present in `customOrder` are sorted by their assigned integer slot.
    /// Items not yet in `customOrder` (e.g. newly launched applications or windows)
    /// append after ordered items, preserving their natural discovery order.
    ///
    /// - Parameters:
    ///   - items: The input list of window groups.
    ///   - customOrder: A mapping from `OrderKey` to its user-assigned slot index.
    /// - Returns: The re-ordered list of window groups.
    public static func applyCustomOrder(
        items: [WindowGroup],
        customOrder: [OrderKey: Int]
    ) -> [WindowGroup] {
        guard !items.isEmpty, !customOrder.isEmpty else { return items }
        
        // Single-pass Decorate-Sort-Undecorate
        // Decorate: map (offset, group) to (offset, group, slot)
        let decorated: [(offset: Int, group: WindowGroup, slot: Int?)] = items.enumerated().map { offset, group in
            let slot: Int?
            if group.isGrouped {
                slot = customOrder[.app(group.bundleID)] ?? group.windows.compactMap { customOrder[.window($0.key)] }.min()
            } else {
                slot = group.windows.compactMap { customOrder[.window($0.key)] }.min() ?? customOrder[.app(group.bundleID)]
            }
            return (offset, group, slot)
        }
        
        // Sort: non-nil slot before nil slot, smaller slot before larger slot, tie-break on initial offset
        let sorted = decorated.sorted { left, right in
            switch (left.slot, right.slot) {
            case let (l?, r?):
                if l != r {
                    return l < r
                }
                return left.offset < right.offset
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.offset < right.offset
            }
        }
        
        // Undecorate: map back to group
        return sorted.map { $0.group }
    }
    
    /// Moves an item within an array of `WindowGroup` from `fromIndex` to `toIndex`,
    /// returning both the re-ordered array and the updated custom order dictionary.
    ///
    /// - Parameters:
    ///   - items: The array of window groups.
    ///   - fromIndex: The source index of the item being dragged.
    ///   - toIndex: The destination index where the item was dropped.
    /// - Returns: A tuple containing the updated array and the new `[OrderKey: Int]` order map.
    public static func moveItem(
        in items: [WindowGroup],
        fromIndex: Int,
        toIndex: Int
    ) -> (reordered: [WindowGroup], newOrder: [OrderKey: Int]) {
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
    
    /// Generates a complete `[OrderKey: Int]` slot map for the given array of window groups.
    /// Maps both `.app(item.bundleID)` and `.window(win.key)` for all windows in `item` to `index`.
    public static func rebuildOrderMap(for items: [WindowGroup]) -> [OrderKey: Int] {
        var map: [OrderKey: Int] = [:]
        map.reserveCapacity(items.count * 2)
        for (index, item) in items.enumerated() {
            map[.app(item.bundleID)] = index
            for win in item.windows {
                map[.window(win.key)] = index
            }
        }
        return map
    }
    
    /// Prunes stale keys from an existing order map that no longer exist among active keys.
    public static func pruneOrderMap(
        _ order: [OrderKey: Int],
        activeKeys: Set<OrderKey>
    ) -> [OrderKey: Int] {
        order.filter { activeKeys.contains($0.key) }
    }
}
