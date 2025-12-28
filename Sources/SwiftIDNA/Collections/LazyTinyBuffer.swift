/// A lazy container that when needed, initializes a `TinyBuffer` with the
/// requested capacity reservation.
///
/// This is useful for when we're not sure if we need to allocate for the array or not, but
/// we have already calculated the capacity that we would need in case of allocation.
///
/// This is tuned to this library's needs so it might need some adjustments for other use cases.
@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct LazyTinyBuffer: ~Copyable {
    @usableFromInline
    var array: TinyBuffer?
    @usableFromInline
    let capacityToReserve: Int

    @inlinable
    init(capacity: Int) {
        self.array = nil
        self.capacityToReserve = capacity
    }

    /// Allows access to the `TinyBuffer` as an `inout` parameter.
    /// On the first call, initializes the buffer with the requested capacity.
    @inlinable
    mutating func withTinyBuffer<T>(_ body: (inout TinyBuffer) -> T) -> T {
        if array != nil {
            return body(&self.array!)
        } else {
            var array = TinyBuffer(preferredCapacity: capacityToReserve)
            let result = body(&array)
            self.array = .some(array)
            return result
        }
    }
}
