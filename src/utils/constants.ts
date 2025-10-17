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
    subspaceProcess: "YjSqaAT6BuQzljSbuad5rE9NDoxL6DiXukT2h3ycn60",

    hyperAosModule: "wal-fUK-YnB9Kp5mN8dgMsSqPSqiGx-0SvwFUSwpDBI",
    authority: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",

    CommonTags
}