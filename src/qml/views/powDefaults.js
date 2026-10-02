.pragma library

// What a node mines with unless the user says otherwise. Quick start writes
// these as they are; Advanced's PoW form starts from them. The node's own
// defaults are every CPU and 4 searches per block, which a desktop can't spare.
var maxThreads = 1
var maxTicketsPerBlock = 1
var claimTickSeconds = 10

// The mining settings alone, in powConfigure's shape. Auto-claim targets are
// left out, which the module reads as "leave them as they are".
function configJson() {
    return JSON.stringify({
        max_threads: maxThreads,
        max_tickets_per_block: maxTicketsPerBlock,
        tick_seconds: claimTickSeconds
    })
}
