import SwiftIDNA
import Testing

@Suite
struct LinkedListTests {
    /// Cross-checks a `LinkedList` against an `Array` built from the very same insertions,
    /// so that any disagreement in the link rewiring or in the cursor shows up as a mismatch.
    @available(SwiftStdlib 5.1, *)
    func checkAgainstArray(insertions: [(value: UInt32, position: Int)]) {
        var list = LinkedList<UInt32>()
        var expected: [UInt32] = []

        for insertion in insertions {
            list.insert(insertion.value, at: insertion.position)
            expected.insert(insertion.value, at: insertion.position)
        }

        #expect(list.count == expected.count)

        var actual: [UInt32] = []
        var iterator = list.makeIterator()
        while let value = iterator.next() {
            actual.append(value)
        }

        #expect(actual == expected)
    }

    @available(SwiftStdlib 5.1, *)
    @Test func insertsAtEveryPositionOfASmallList() {
        for count in 0...8 {
            for position in 0...count {
                var insertions = (0..<count).map { (value: UInt32($0), position: $0) }
                insertions.append((value: 999, position: position))
                checkAgainstArray(insertions: insertions)
            }
        }
    }

    /// Walks well past the initial arena capacity, so that the list has to reallocate several
    /// times and every node index has to survive the move.
    @available(SwiftStdlib 5.1, *)
    @Test(arguments: [1, 63, 64, 65, 127, 128, 129, 300])
    func randomizedInsertionsGrowTheArena(count: Int) {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            var insertions: [(value: UInt32, position: Int)] = []
            for idx in 0..<count {
                insertions.append(
                    (value: UInt32(idx), position: Int.random(in: 0...idx, using: &generator))
                )
            }
            checkAgainstArray(insertions: insertions)
        }
    }

    @available(SwiftStdlib 5.1, *)
    @Test func appendsInOrder() {
        var list = LinkedList<UInt32>()
        for value in 0..<200 as Range<UInt32> {
            list.append(value)
        }

        var actual: [UInt32] = []
        var iterator = list.makeIterator()
        while let value = iterator.next() {
            actual.append(value)
        }

        #expect(actual == Array(0..<200 as Range<UInt32>))
    }

    /// `removeAll()` keeps the arena, so a reused list has to forget its head and its cursor
    /// without forgetting the capacity it already paid for.
    @available(SwiftStdlib 5.1, *)
    @Test func reusesTheArenaAfterRemoveAll() {
        var list = LinkedList<UInt32>()
        var generator = SystemRandomNumberGenerator()

        for round in 0..<50 {
            list.removeAll()
            #expect(list.count == 0)

            var iterator = list.makeIterator()
            #expect(iterator.next() == nil)

            var expected: [UInt32] = []
            for idx in 0..<(round &+ 1) {
                let position = Int.random(in: 0...idx, using: &generator)
                list.insert(UInt32(idx), at: position)
                expected.insert(UInt32(idx), at: position)
            }

            var actual: [UInt32] = []
            iterator = list.makeIterator()
            while let value = iterator.next() {
                actual.append(value)
            }

            #expect(actual == expected)
        }
    }
}
