/// A singly linked list of bitwise-copyable elements, held in a single flat heap
/// allocation and addressed with 32-bit node indices.
///
/// Every node lives in a contiguous arena that is filled from front to back: a node keeps the
/// slot it was first written to for as long as the list holds it, and only the links between
/// nodes are ever rewired. An insertion therefore never moves an element, which is what makes
/// this construct interesting for algorithms that repeatedly splice items into the middle of a
/// sequence and only read the result back once, at the end.
///
///     var list = LinkedList<UInt32>()
///     list.append(1)
///     list.append(3)
///     list.insert(2, at: 1)
///     // `list` now holds 1, 2, 3
///
/// The arena is allocated lazily, on the first insertion, and it is not released until the list
/// is destroyed. `removeAll()` keeps it, so a list that is reused across many short sequences
/// pays for a single allocation, plus however many reallocations the longest of those sequences
/// forced.
///
/// Positions are logical: position 0 is the first element of the list, no matter which arena
/// slot it happens to occupy. Resolving a position to a node means walking the links, so an
/// insertion only costs O(1) once the node in front of it is known. The list caches the node it
/// last inserted at, which lets appending, and inserting at a position at or after the previous
/// one, walk just the distance between the two positions.
///
/// Because nodes address each other with `Int32`, a list can hold at most `Int32.max` elements.
@available(SwiftStdlib 5.1, *)
@safe
@usableFromInline
package struct LinkedList<Element: BitwiseCopyable>: ~Copyable {
    /// The arena, of which only the first `_count` slots are initialized.
    @usableFromInline
    var _storage: UnsafeMutableBufferPointer<Node>

    @usableFromInline
    var _count: Int

    /// The arena index of the first node, or `-1` when the list is empty.
    @usableFromInline
    var _headIdx: Int32

    /// The arena index of the node at `_cursorPosition`, or `-1` when there is no cursor.
    @usableFromInline
    var _cursorIdx: Int32

    /// The position of the node at `_cursorIdx`.
    @usableFromInline
    var _cursorPosition: Int

    deinit {
        unsafe _storage.deallocate()
    }
}

/// The capacity a linked list's arena grows to, given the capacity it has outgrown.
///
/// Unlike the 1.5x curve `UniqueArray` uses, this starts at a capacity that already covers a
/// whole IDNA label and doubles from there, because the lists this library builds are either
/// small enough to never reallocate or are fed an input that is not a valid label at all.
@available(SwiftStdlib 5.1, *)
@inlinable
@_transparent
func _growLinkedListCapacity(_ capacity: Int) -> Int {
    capacity == 0 ? 64 : capacity &* 2
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// One element of the list, alongside the arena index of the element that follows it.
    @usableFromInline
    struct Node {
        /// The arena index of the next node, or `-1` when this is the last node.
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
    /// Initializes a new linked list with no elements and no arena.
    ///
    /// The arena is allocated by the first insertion, so an empty list costs nothing.
    ///
    /// - Complexity: O(1)
    @inlinable
    package init() {
        unsafe _storage = UnsafeMutableBufferPointer(start: nil, count: 0)
        _count = 0
        _headIdx = -1
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

    /// The maximum number of elements this list can hold without having to reallocate its arena.
    ///
    /// - Complexity: O(1)
    @inlinable
    @_transparent
    var capacity: Int {
        unsafe _assumeNonNegative(_storage.count)
    }

    /// A Boolean value indicating whether the arena is fully populated.
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
    /// Makes room for one more element, reallocating the arena if it is full.
    ///
    /// - Complexity: O(1) when the arena has room, O(`count`) otherwise.
    @inlinable
    @_transparent
    mutating func _ensureFreeCapacity() {
        guard isFull else { return }
        _growStorage()
    }

    /// Replaces the arena with a larger one, moving every node over to it.
    ///
    /// Node indices are positions within the arena, and the nodes are moved without reordering
    /// them, so every existing link stays valid across the move.
    ///
    /// - Complexity: O(`count`)
    @inlinable
    @inline(never)
    mutating func _growStorage() {
        let newCapacity = _growLinkedListCapacity(capacity)
        /// Nodes address each other with `Int32`, so the arena cannot grow past `Int32.max`.
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
    /// Returns the arena index of the node at the specified position.
    ///
    /// The walk starts at the cursor when the cursor has not already passed `position`, and at
    /// the head of the list otherwise, so it never walks more than `position` links.
    ///
    /// - Parameter position: The position to resolve. `position` must be a valid position in the
    ///   list.
    ///
    /// - Returns: The arena index of the node currently at `position`.
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
    /// No existing element moves: the new element takes the first free slot of the arena, and
    /// the element in front of it is relinked to point at it.
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
        insert(element, at: count)
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// Removes all elements from the list, keeping the arena.
    ///
    /// The arena is not released, so refilling the list does not have to allocate again.
    ///
    /// - Complexity: O(1)
    @inlinable
    package mutating func removeAll() {
        _count = 0
        _headIdx = -1
        _cursorIdx = -1
        _cursorPosition = 0
    }
}

@available(SwiftStdlib 5.1, *)
extension LinkedList {
    /// A walk over the elements of a list, from one of its nodes to the end.
    ///
    /// The iterator addresses the arena directly rather than borrowing the list, so it can be
    /// used from contexts that cannot hold onto a noncopyable value. Inserting into the list
    /// invalidates every iterator made from it, because the insertion may have reallocated the
    /// arena; only iterate a list you are done inserting into.
    @safe
    @usableFromInline
    package struct Iterator {
        @usableFromInline
        let _storage: UnsafeMutableBufferPointer<Node>

        /// The arena index of the node to return next, or `-1` when the walk is over.
        @usableFromInline
        var _nodeIdx: Int32

        @inlinable
        init(_storage: UnsafeMutableBufferPointer<Node>, _nodeIdx: Int32) {
            unsafe self._storage = _storage
            self._nodeIdx = _nodeIdx
        }

        /// Advances to the next element and returns it, or `nil` if the walk is over.
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

    /// Returns an iterator over the elements of this list, in order.
    ///
    /// - Complexity: O(1)
    @inlinable
    package func makeIterator() -> Iterator {
        unsafe Iterator(_storage: _storage, _nodeIdx: _headIdx)
    }
}
