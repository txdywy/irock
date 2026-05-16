# Benchmark Runner

Run performance evidence from the repository root:

```bash
swift run irock-benchmark-runner packet-processor
swift run irock-benchmark-runner runtime-packet-batch
swift run irock-benchmark-runner routing-lookup
```

The packet processor benchmark reports packet count, dropped count, elapsed nanoseconds, average nanoseconds per packet, and packets per second. The runtime packet benchmark reports packet count, written count, dropped count, elapsed nanoseconds, average nanoseconds per packet, and packets per second. The routing benchmark reports lookup count, elapsed nanoseconds, average nanoseconds per lookup, and lookups per second.
