// Profile Input Interfaces
export interface ICreateProfile {
    pfp?: string
    banner?: string
    bio?: string
}

// Server Input Interfaces
export interface ICreateServer {
    serverName: string
    serverDescription?: string
    serverPfp?: string
    serverBanner?: string
}

export interface IUpdateServer extends ICreateServer {
    serverId: string
}