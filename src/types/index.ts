
// Export all input types under Inputs namespace
import * as InputTypes from "./inputs"
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
    ServerEvent,
    EPermissions
} from "./subspace"
