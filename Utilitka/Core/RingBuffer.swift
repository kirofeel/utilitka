/// Fixed-size history: once full, each append overwrites the oldest element.
struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    var count: Int { storage.count }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Oldest to newest.
    var elements: [Element] {
        guard storage.count == capacity, head != 0 else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    var last: Element? {
        guard !storage.isEmpty else { return nil }
        if storage.count < capacity { return storage.last }
        return storage[(head - 1 + capacity) % capacity]
    }
}
