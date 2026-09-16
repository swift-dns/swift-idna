/// A singly linked list of bitwise-copyable elements, held in a single heap allocation.
///
///     var list = LinkedList<UInt32>()
///     list.append(1)
///     list.append(3)
///     list.insert(2, at: 1)
///     // `list` now holds 1, 2, 3
@available(SwiftStdlib 5.1, *)
@safe
@usableFromInline
package struct LinkedList<Element: BitwiseCopyable>: ~Copyable {
    /// The buffer, of which only the first `_count` slots are initialized.
    @usableFromInline
    var _storage: UnsafeMutableBufferPointer<Node>

    @usableFromInline
    var _count: Int

    /// The slot of the first node, or `-1` when the list is empty.
    @usableFromInline
    var _headIdx: Int32

    /// The slot of the last node, or `-1` when the list is empty.
    @usableFromInline
    var _tailIdx: Int32

    /// The slot of the node at `_cursorPosition`, or `-1` when there is no cursor.
    @usableFromInline
    var _cursorIdx: Int32

    /// The position of the node at `_cursorIdx`.
    @usableFromInline
    var _cursorPosition: Int

    deinit {
        unsafe _storage.deallocate()
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// One element of the list, alongside the slot of the element that follows it.
    @usableFromInline
    struct Node {
        /// The slot of the next node, or `-1` when this is the last node.
        @usableFromInline
        var nextIdx: Int32

        @usableFromInline
        var value: Element

        @inlinable
        init(nextIdx: Int32, value: Element) {
            self.nextIdx = nextIdx
            self.value = value
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// Initializes a new linked list with no elements and no buffer.
    ///
    /// The buffer is allocated by the first insertion, so an empty list costs nothing.
    ///
    /// - Complexity: O(1)
    @inlinable
    package init() {
        unsafe _storage = UnsafeMutableBufferPointer(start: nil, count: 0)
        _count = 0
        _headIdx = -1
        _tailIdx = -1
        _cursorIdx = -1
        _cursorPosition = 0
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// The number of elements in the list.
    ///
    /// - Complexity: O(1)
    @inlinable
    @_transparent
    package var count: Int {
        _assumeNonNegative(_count)
    }

    /// The maximum number of elements this list can hold without having to reallocate its buffer.
    ///
    /// - Complexity: O(1)
    @inlinable
    @_transparent
    var capacity: Int {
        unsafe _assumeNonNegative(_storage.count)
    }

    /// A Boolean value indicating whether the buffer is fully populated.
    /// If this property returns true, then the next insertion has to reallocate.
    ///
    /// - Complexity: O(1)
    @inlinable
    @_transparent
    var isFull: Bool {
        count == capacity
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// Makes room for one more element, reallocating the buffer if it is full.
    ///
    /// - Complexity: O(1) when the buffer has room, O(`count`) otherwise.
    @inlinable
    @_transparent
    mutating func _ensureFreeCapacity() {
        guard isFull else { return }
        _growStorage()
    }

    /// Replaces the buffer with a larger one, moving every node over to it.
    ///
    /// A node is addressed by its slot in the buffer, and the nodes are moved without reordering
    /// them, so every existing link stays valid across the move.
    ///
    /// - Complexity: O(`count`)
    @inlinable
    @inline(never)
    mutating func _growStorage() {
        let newCapacity = capacity == 0 ? 64 : capacity &* 2
        /// Nodes address each other with `Int32`, so the buffer cannot grow past `Int32.max`.
        assert(newCapacity <= Int(Int32.max))
        let newStorage = UnsafeMutableBufferPointer<Node>.allocate(capacity: newCapacity)
        if capacity != 0 {
            let initializedRange = unsafe Range<Int>(uncheckedBounds: (0, count))
            let initialized = unsafe _storage.extracting(initializedRange)
            let last = unsafe newStorage.moveInitialize(fromContentsOf: initialized)
            assert(last == count)
            unsafe _storage.deallocate()
        }
        unsafe _storage = newStorage
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// Returns the slot of the node at the specified position.
    ///
    /// The walk starts at the cursor when the cursor has not already passed `position`, and at
    /// the head of the list otherwise, so it never walks more than `position` links.
    ///
    /// - Parameter position: The position to resolve. `position` must be a valid position in the
    ///   list.
    ///
    /// - Returns: The slot of the node currently at `position`.
    ///
    /// - Complexity: O(`position`)
    @inlinable
    func _nodeIdx(at position: Int) -> Int32 {
        assert(position >= 0 && position < count)
        var nodeIdx: Int32
        var remainingSteps: Int
        if _cursorIdx >= 0, _cursorPosition <= position {
            nodeIdx = _cursorIdx
            remainingSteps = position &- _cursorPosition
        } else {
            nodeIdx = _headIdx
            remainingSteps = position
        }
        while remainingSteps > 0 {
            nodeIdx = unsafe _storage[Int(nodeIdx)].nextIdx
            remainingSteps &-= 1
        }
        return nodeIdx
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// Inserts a new element into the list at the specified position.
    ///
    /// The new element is inserted before the element currently at the specified position. If
    /// you pass the list's `count` as the `position` parameter, then the new element is appended
    /// to the list.
    ///
    /// - Parameter element: The new element to insert into the list.
    /// - Parameter position: The position at which to insert the new element. `position` must be
    ///   a valid position in the list, or its `count`.
    ///
    /// - Complexity: O(`position`) in the worst case, O(1) when `position` is at or after the
    ///   position of the previous insertion.
    @inlinable
    package mutating func insert(_ element: Element, at position: Int) {
        assert(position >= 0 && position <= count)
        _ensureFreeCapacity()

        let newIdx = Int32(truncatingIfNeeded: count)

        if position == 0 {
            unsafe _storage.initializeElement(
                at: count,
                to: Node(nextIdx: _headIdx, value: element)
            )
            _headIdx = newIdx
        } else {
            let previousIdx = Int(_nodeIdx(at: position &- 1))
            unsafe _storage.initializeElement(
                at: count,
                to: Node(nextIdx: unsafe _storage[previousIdx].nextIdx, value: element)
            )
            unsafe _storage[previousIdx].nextIdx = newIdx
        }

        if position == count {
            _tailIdx = newIdx
        }

        _count &+= 1
        _cursorIdx = newIdx
        _cursorPosition = position
    }

    /// Adds a new element at the end of the list.
    ///
    /// - Parameter element: The element to append to the list.
    ///
    /// - Complexity: O(1)
    @inlinable
    package mutating func append(_ element: Element) {
        _ensureFreeCapacity()

        let position = count
        let newIdx = Int32(truncatingIfNeeded: position)
        /// The new node ends the list, and the node it follows ended it until now, so neither
        /// of the two links has to be read before being written.
        unsafe _storage.initializeElement(at: position, to: Node(nextIdx: -1, value: element))

        if _tailIdx >= 0 {
            unsafe _storage[Int(_tailIdx)].nextIdx = newIdx
        } else {
            _headIdx = newIdx
        }

        _count &+= 1
        _tailIdx = newIdx
        _cursorIdx = newIdx
        _cursorPosition = position
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// Removes all elements from the list, keeping the allocated capacity.
    ///
    /// - Complexity: O(1)
    @inlinable
    package mutating func removeAll() {
        _count = 0
        _headIdx = -1
        _tailIdx = -1
        _cursorIdx = -1
        _cursorPosition = 0
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    ///
    @safe
    @usableFromInline
    package struct Iterator {
        @usableFromInline
        let _storage: UnsafeMutableBufferPointer<Node>

        /// The slot of the node to return next, or `-1` when the walk is over.
        @usableFromInline
        var _nodeIdx: Int32

        @inlinable
        init(_storage: UnsafeMutableBufferPointer<Node>, _nodeIdx: Int32) {
            unsafe self._storage = _storage
            self._nodeIdx = _nodeIdx
        }

        /// Advances to the next element and returns it, or `nil` if there are no more elements.
        ///
        /// - Complexity: O(1)
        @inlinable
        package mutating func next() -> Element? {
            guard _nodeIdx >= 0 else {
                return nil
            }
            let node = unsafe _storage[Int(_nodeIdx)]
            _nodeIdx = node.nextIdx
            return node.value
        }
    }

    /// Returns an iterator over the elements of this list.
    ///
    /// - Complexity: O(1)
    @inlinable
    package func makeIterator() -> Iterator {
        unsafe Iterator(_storage: _storage, _nodeIdx: _headIdx)
    }
}
