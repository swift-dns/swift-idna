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
