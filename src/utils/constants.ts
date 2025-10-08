import type { Tag } from "../types/subspace";

const CommonTags: Tag[] = [
    { name: "App-Name", value: "Subspace-SDK" },
    { name: "App-Version", value: "0.0.5" },
]

export const Defaults = {
    HB_URL: "https://hb.arweave.tech",
    // HB_URL: "https://scheduler.forward.computer",
    GATEWAY_URL: "https://arweave.net"
}

export const Constants = {
    subspaceProcess: "rbvA4lz6sa124FShJwb2xxJ8Ofa0bSK2mAJrGyTMmJQ",

    hyperAosModule: "wal-fUK-YnB9Kp5mN8dgMsSqPSqiGx-0SvwFUSwpDBI",
    authority: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",

    CommonTags
}