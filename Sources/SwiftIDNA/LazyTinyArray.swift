@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct LazyTinyArray: ~Copyable {
    @usableFromInline
    var array: TinyArray?
    @usableFromInline
    let capacityToReserve: Int

    @inlinable
    init(capacity: Int) {
        self.array = nil
        self.capacityToReserve = capacity
    }

    @inlinable
    mutating func withTinyArray<T>(_ body: (inout TinyArray) -> T) -> T {
        if array != nil {
            return body(&self.array!)
        } else {
            var array = TinyArray(preferredCapacity: capacityToReserve)
            let result = body(&array)
            self.array = .some(array)
            return result
        }
    }
}
