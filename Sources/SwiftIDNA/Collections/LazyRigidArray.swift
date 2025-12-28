public import BasicContainers

/// A lazy container that when needed, initializes a `RigidArray` of a given integer type with
/// the requested capacity reservation.
///
/// This is useful for when we're not sure if we need to allocate for the array or not, but
/// we have already calculated the capacity that we would need in case of allocation.
///
/// This is tuned to this library's needs so it might need some adjustments for other use cases.
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

    /// Allows access to the `RigidArray` as an `OutputSpan<Integer>`.
    ///
    /// On the first call, initialize all the elements to `0` so they are modifiable out of order.
    /// This behavior is needed for the implementation of the IDNA conversion algorithm.
    /// Tests will immediately crash if the code is changed to not initialize the elements.
    @inlinable
    mutating func withRigidArrayOutputSpan<T>(_ body: (inout OutputSpan<Integer>) -> T) -> T {
        if array != nil {
            return self.array!.edit { output in
                body(&output)
            }
        } else {
            var array = RigidArray<Integer>(capacity: capacityToReserve)
            let result = array.edit { output in
                /// The implementation relies on all indices being available to modify out of order,
                /// so we fill the array with zeros
                output.append(repeating: 0, count: capacityToReserve)
                return body(&output)
            }
            self.array = .some(array)
            return result
        }
    }
}
