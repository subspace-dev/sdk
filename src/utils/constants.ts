import type { Tag } from "../types/subspace";

const CommonTags: Tag[] = [
    { name: "App-Name", value: "Subspace-SDK" },
    { name: "App-Version", value: "0.0.5" },
]

export const Defaults = {
    HB_URL: "https://scheduler.forward.computer",
    GATEWAY_URL: "https://arweave.net"
}

export const Constants = {
    subspaceProcess: "LIvKAMYFyD2vgEfvCaG_PrkxQpH7tPPvm2JFNs5MK2s",

    hyperAosModule: "xVcnPK8MPmcocS6zwq1eLmM2KhfyarP8zzmz3UVi1g4",
    authority: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",

    CommonTags
}