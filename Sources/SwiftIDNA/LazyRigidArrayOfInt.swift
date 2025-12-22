public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct LazyRigidArrayOfInt: ~Copyable {
    @usableFromInline
    var array: RigidArray<Int>?
    @usableFromInline
    let capacityToReserve: Int

    @inlinable
    init(capacity: Int) {
        self.array = nil
        self.capacityToReserve = capacity
    }

    @inlinable
    mutating func withRigidArray<T>(_ body: (inout RigidArray<Int>) -> T) -> T {
        if array != nil {
            return body(&self.array!)
        } else {
            var array = RigidArray<Int>(capacity: capacityToReserve)
            for _ in 0..<capacityToReserve {
                array.append(0)
            }
            let result = body(&array)
            self.array = .some(array)
            return result
        }
    }
}
