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
    subspaceProcess: "veX9Kmg3DtYbSAUnC1sXhrwAGOn1CU61i9CvsxWtyoA",

    hyperAosModule: "xVcnPK8MPmcocS6zwq1eLmM2KhfyarP8zzmz3UVi1g4",
    authority: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",

    CommonTags
}