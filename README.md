# SieveCache

`SieveCache` is a memory-efficient cache built in Zig that uses a "sieve" or **clock-based** algorithm for its eviction policy. This approach offers a smart way to manage data, ensuring that frequently used items stay in the cache longer.

### How It Works

Imagine a circular list of all the items in your cache, with a hand that moves around the list like the hand of a clock. Each item has a **`visited`** bit that is either `0` or `1`.

* **Accessing an item**: If an item is already in the cache (a **cache hit**), the `visited` bit for that item is flipped to `1`.
* **Adding a new item**: If a new item is added to the cache (a **cache miss**), it's placed at the head of the list.
* **Eviction**: When the cache is full, the "hand" starts moving.
    * If the hand finds an item with its `visited` bit set to `1`, it flips the bit back to `0` and moves on. This gives the item a **"second chance"**.
    * If the hand finds an item with its `visited` bit set to `0`, it means the item hasn't been used recently, so it's **evicted** from the cache to make room for the new item.

This method is great for systems where you need a simple but effective way to handle cache evictions without the overhead of more complex algorithms like LRU (Least Recently Used).

### Usage

Here's how to use the `SieveCache`:

1.  **Initialize**: Create a new `SieveCache` with an allocator and a maximum capacity.
    ```zig
    var cache = SieveCache(u32).init(allocator, 3);
    ```
2.  **Access items**: Use the `access` function to either retrieve an item (setting its `visited` bit) or add a new one (potentially triggering an eviction).
    ```zig
    try cache.access(10); // Adds item 10
    try cache.access(20); // Adds item 20
    try cache.access(30); // Adds item 30
    
    // Cache is full. This will evict the least recently used item (10).
    try cache.access(40); 
    ```
3.  **Clean up**: Remember to call `deinit()` when you are done to free all the allocated memory.
    ```zig
    defer cache.deinit();
    ```

This simple process provides a robust and memory-safe caching solution.
