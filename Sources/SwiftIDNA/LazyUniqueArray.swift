public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct LazyUniqueArray<Element>: ~Copyable {
    @usableFromInline
    var array: UniqueArray<Element>?
    @usableFromInline
    let capacityToReserve: Int

    @inlinable
    init(capacity: Int) {
        self.array = nil
        self.capacityToReserve = capacity
    }

    @inlinable
    mutating func withUniqueArray<T>(_ body: (inout UniqueArray<Element>) -> T) -> T {
        if array != nil {
            return body(&self.array!)
        } else {
            var array = UniqueArray<Element>(capacity: capacityToReserve)
            let result = body(&array)
            self.array = .some(array)
            return result
        }
    }
}
