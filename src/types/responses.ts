import { IDirectMessageReadOnly, IEventReadOnly, IMessageReadOnly } from "./subspace"

export type DMResponse = {
    messages: IDirectMessageReadOnly[]
    events: IEventReadOnly[]
}

export type GetMessagesResponse = {
    messages: IMessageReadOnly[]
    channelScope: "single" | "all"
}