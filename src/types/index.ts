import { toast } from "sonner"

// Export all input types under Inputs namespace
import * as InputTypes from "./inputs"

declare global {
    interface Window {
        toast: typeof toast
    }
}

export namespace Inputs {
    export type ICreateProfile = InputTypes.ICreateProfile
    export type ICreateServer = InputTypes.ICreateServer
    export type IUpdateServer = InputTypes.IUpdateServer
    export type ICreateCategory = InputTypes.ICreateCategory
    export type IUpdateCategory = InputTypes.IUpdateCategory
    export type IDeleteCategory = InputTypes.IDeleteCategory
    export type ICreateChannel = InputTypes.ICreateChannel
    export type IUpdateChannel = InputTypes.IUpdateChannel
    export type IDeleteChannel = InputTypes.IDeleteChannel
    export type ICreateRole = InputTypes.ICreateRole
    export type IUpdateRole = InputTypes.IUpdateRole
    export type IDeleteRole = InputTypes.IDeleteRole
    export type IAssignRole = InputTypes.IAssignRole
    export type IUnassignRole = InputTypes.IUnassignRole
    export type ISendMessage = InputTypes.ISendMessage
    export type IUpdateMessage = InputTypes.IUpdateMessage
    export type IDeleteMessage = InputTypes.IDeleteMessage
    export type ISendDM = InputTypes.ISendDM
    export type IEditDM = InputTypes.IEditDM
    export type IDeleteDM = InputTypes.IDeleteDM
    export type IUpdateMember = InputTypes.IUpdateMember
    export type IKickMember = InputTypes.IKickMember
    export type IBanMember = InputTypes.IBanMember
    export type IUnbanMember = InputTypes.IUnbanMember
    export type IGetMember = InputTypes.IGetMember
}

// Export all output/entity types
export type {
    IProfile,
    IBot,
    IServer,
    IMember,
    IRole,
    ICategory,
    IChannel,
    IMessage,
    IAttachment,
    INotification,
    Tag,
    ServerEvent
} from "./subspace"

// Export EPermissions as a value (enum)
import { EPermissions } from "./subspace"
export { EPermissions }
