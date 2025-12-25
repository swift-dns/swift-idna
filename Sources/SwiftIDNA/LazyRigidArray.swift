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
    mutating func withRigidArray<T>(_ body: (inout RigidArray<Integer>) -> T) -> T {
        if array != nil {
            return body(&self.array!)
        } else {
            var array = RigidArray<Integer>(capacity: capacityToReserve)
            /// FIXME: This capacity reserve here like this looks weird.
            /// Is there a better way to do this without filling the array with zeros?
            array.edit { output in
                output.withUnsafeMutableBufferPointer { buffer, initializedCount in
                    buffer.initialize(repeating: 0)
                    initializedCount = capacityToReserve
                }
            }
            let result = body(&array)
            self.array = .some(array)
            return result
        }
    }
}
