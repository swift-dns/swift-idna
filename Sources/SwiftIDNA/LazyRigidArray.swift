public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct LazyRigidArray<Integer: FixedWidthInteger>: ~Copyable {
    @usableFromInline
    var array: RigidArray<Integer>?
    @usableFromInline
    let capacityToReserve: Int

    @inlinable
    init(capacity: Int) {
        self.array = nil
        self.capacityToReserve = capacity
    }

    @inlinable
    mutating func withRigidArrayOutputSpan<T>(_ body: (inout OutputSpan<Integer>) -> T) -> T {
        if array != nil {
            return self.array!.edit { output in
                body(&output)
            }
        } else {
            var array = RigidArray<Integer>(capacity: capacityToReserve)
            let result = array.edit { output in
                /// The implementation relies on all indices being available to modify,
                /// so we fill the array with zeros
                output.append(repeating: 0, count: capacityToReserve)
                return body(&output)
            }
            self.array = .some(array)
            return result
        }
    }
}
