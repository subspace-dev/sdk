export type DMResponse = {
    messages: any[];
    events: any[];
};
export type GetMessagesResponse = {
    messages: any[];
    channelScope: "single" | "all";
};
