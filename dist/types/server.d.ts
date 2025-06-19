import { AoClient, AoSigner } from "./types/ao";
import { assignRoleParams, createCategoryParams, createChannelParams, createRoleParams, editMessageParams, getMessagesParams, sendMessageParams, unassignRoleParams, updateCategoryParams, updateChannelParams, updateMemberParams, updateRoleParams } from "./types/inputs";
import { ICategoryReadOnly, IChannelReadOnly, IMember, IMemberReadOnly, IMessageReadOnly, IRoleReadOnly, IServer, IServerReadOnly } from "./types/subspace";
import { GetMessagesResponse } from "./types/responses";
export declare class ServerReadOnly implements IServerReadOnly {
    ao: AoClient;
    serverId: string;
    ownerId: string;
    name: string;
    logo: string;
    channels: IChannelReadOnly[];
    categories: ICategoryReadOnly[];
    roles: IRoleReadOnly[];
    constructor(data: IServerReadOnly, ao: AoClient);
    getMember(userId: string): Promise<IMemberReadOnly>;
    getAllMembers(): Promise<IMemberReadOnly[]>;
}
export declare class Server extends ServerReadOnly implements IServer {
    private signer?;
    constructor(data: IServerReadOnly, ao: AoClient, signer?: AoSigner);
    getMember(userId: string): Promise<IMember>;
    getAllMembers(): Promise<IMember[]>;
    updateMember(params: updateMemberParams): Promise<IMember>;
    kickMember(userId: string): Promise<boolean>;
    banMember(userId: string): Promise<boolean>;
    unbanMember(userId: string): Promise<boolean>;
    createCategory(params: createCategoryParams): Promise<boolean>;
    updateCategory(params: updateCategoryParams): Promise<boolean>;
    deleteCategory(categoryId: string): Promise<boolean>;
    createChannel(params: createChannelParams): Promise<boolean>;
    updateChannel(params: updateChannelParams): Promise<boolean>;
    deleteChannel(channelId: string): Promise<boolean>;
    createRole(params: createRoleParams): Promise<boolean>;
    updateRole(params: updateRoleParams): Promise<boolean>;
    deleteRole(roleId: string): Promise<boolean>;
    assignRole(params: assignRoleParams): Promise<boolean>;
    unassignRole(params: unassignRoleParams): Promise<boolean>;
    sendMessage(params: sendMessageParams): Promise<boolean>;
    editMessage(params: editMessageParams): Promise<boolean>;
    deleteMessage(messageId: string): Promise<boolean>;
    getSingleMessage(messageId: string): Promise<IMessageReadOnly>;
    getMessages(params: getMessagesParams): Promise<GetMessagesResponse>;
}
