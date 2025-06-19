import { deleteDMParams, editDMParams, getDMsParams, sendDMParams, updateProfileParams } from "./types/inputs";
import { INotificationReadOnly, IProfile } from "./types/subspace";
import { AoClient, AoSigner } from "./types/ao";
import { DMResponse } from "./types/responses";
export declare class Profile implements IProfile {
    private ao;
    private signer?;
    userId: string;
    pfp?: string;
    dmProcess?: string;
    delegations?: string[];
    serversJoined?: Array<{
        orderId: number;
        serverId: string;
    }>;
    friends?: {
        accepted: string[];
        sent: string[];
        received: string[];
    };
    constructor(data: IProfile, ao: AoClient, signer?: AoSigner);
    getNotifications(): Promise<Array<INotificationReadOnly>>;
    updateProfile(params: updateProfileParams): Promise<Profile>;
    addDelegation(): Promise<boolean>;
    removeDelegation(): Promise<boolean>;
    removeAllDelegations(): Promise<boolean>;
    getDMs(params: getDMsParams): Promise<DMResponse>;
    sendDM(params: sendDMParams): Promise<boolean>;
    deleteDM(params: deleteDMParams): Promise<boolean>;
    editDM(params: editDMParams): Promise<boolean>;
    sendFriendRequest(userId: string): Promise<boolean>;
    acceptFriendRequest(userId: string): Promise<boolean>;
    rejectFriendRequest(userId: string): Promise<boolean>;
    removeFriend(userId: string): Promise<boolean>;
}
