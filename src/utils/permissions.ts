import { EPermissions } from "../types/subspace"
import type { IMember, IRole, IServer } from "../types/subspace"

export { EPermissions }

// Permission definitions for UI display
export const PermissionDefinitions = [
    {
        id: "SEND_MESSAGES",
        name: "Send Messages",
        description: "Send messages in text channels",
        value: EPermissions.SEND_MESSAGES,
        category: "General"
    },
    {
        id: "MANAGE_MESSAGES",
        name: "Manage Messages",
        description: "Delete and edit messages from other users",
        value: EPermissions.MANAGE_MESSAGES,
        category: "General"
    },
    {
        id: "ATTACHMENTS",
        name: "Attach Files",
        description: "Upload files and images to messages",
        value: EPermissions.ATTACHMENTS,
        category: "General"
    },
    {
        id: "MENTION_EVERYONE",
        name: "Mention Everyone",
        description: "Use @everyone and @here mentions",
        value: EPermissions.MENTION_EVERYONE,
        category: "General"
    },
    {
        id: "MANAGE_NICKNAMES",
        name: "Manage Nicknames",
        description: "Change other users' nicknames",
        value: EPermissions.MANAGE_NICKNAMES,
        category: "Members"
    },
    {
        id: "MANAGE_MEMBERS",
        name: "Manage Members",
        description: "Modify member settings and permissions",
        value: EPermissions.MANAGE_MEMBERS,
        category: "Members"
    },
    {
        id: "KICK_MEMBERS",
        name: "Kick Members",
        description: "Remove members from the server",
        value: EPermissions.KICK_MEMBERS,
        category: "Members"
    },
    {
        id: "BAN_MEMBERS",
        name: "Ban Members",
        description: "Ban members from the server",
        value: EPermissions.BAN_MEMBERS,
        category: "Members"
    },
    {
        id: "MANAGE_CHANNELS",
        name: "Manage Channels",
        description: "Create, edit, and delete channels",
        value: EPermissions.MANAGE_CHANNELS,
        category: "Server"
    },
    {
        id: "MANAGE_ROLES",
        name: "Manage Roles",
        description: "Create, edit, and delete roles",
        value: EPermissions.MANAGE_ROLES,
        category: "Server"
    },
    {
        id: "MANAGE_SERVER",
        name: "Manage Server",
        description: "Edit server settings and information",
        value: EPermissions.MANAGE_SERVER,
        category: "Server"
    },
    {
        id: "MANAGE_BOTS",
        name: "Manage Bots",
        description: "Add and remove bots from the server",
        value: EPermissions.MANAGE_BOTS,
        category: "Server"
    },
    {
        id: "ADMINISTRATOR",
        name: "Administrator",
        description: "All permissions (overrides other permissions)",
        value: EPermissions.ADMINISTRATOR,
        category: "Advanced"
    }
] as const

// Helper functions for permission manipulation
// export const PermissionHelpers = {
//     // Check if a permission value includes a specific permission
//     hasPermission: (permissions: number, permission: number): boolean => {
//         return (permissions & permission) === permission
//     },

//     // Add a permission to a permission value
//     addPermission: (permissions: number, permission: number): number => {
//         return permissions | permission
//     },

//     // Remove a permission from a permission value
//     removePermission: (permissions: number, permission: number): number => {
//         return permissions & ~permission
//     },

//     // Get an array of permission objects that are enabled
//     getEnabledPermissions: (permissions: number) => {
//         return PermissionDefinitions.filter(perm =>
//             PermissionHelpers.hasPermission(permissions, perm.value)
//         )
//     },

//     // Calculate total permissions value from array of permission IDs
//     calculatePermissions: (permissionIds: string[]): number => {
//         return permissionIds.reduce((total, permId) => {
//             const perm = PermissionDefinitions.find(p => p.id === permId)
//             return perm ? total | perm.value : total
//         }, 0)
//     },

//     // Check if user has administrator permission (overrides all others)
//     isAdministrator: (permissions: number): boolean => {
//         return PermissionHelpers.hasPermission(permissions, Permissions.ADMINISTRATOR)
//     }
// }
export class Permissions {
    static bits = EPermissions
    static definitions = PermissionDefinitions
    static maxValue = Object.values(EPermissions).reduce((acc, val) => acc | val, 0)


    static isValid(permission: number): boolean {
        if (typeof permission !== 'number' || permission < 0) {
            return false
        }

        // Check if permission only contains valid bits
        return (permission & Permissions.maxValue) === permission
    }

    static roleHas(role: IRole, permission: number): boolean {
        if (!role || !Permissions.isValid(role.permissions) || !Permissions.isValid(permission)) {
            return false
        }

        // Match Lua implementation: simple bitwise check without administrator override
        return ((role.permissions || 0) & permission) === permission
    }

    static memberHas(member: IMember, server: IServer, permission: number): boolean {
        if (!member || !server || !Permissions.isValid(permission)) {
            return false
        }

        // Server owner has all permissions
        if (member.id === server.profile.owner) {
            return true
        }

        // If no roles, return false
        if (!member.roles || Object.keys(member.roles).length === 0) {
            return false
        }

        // Check if any role has the permission
        for (const roleId of Object.keys(member.roles)) {
            const role = server.roles[roleId]
            if (role && Permissions.roleHas(role, permission)) {
                return true
            }
        }

        return false
    }

    // Check if a member has any of the specified permissions (matches Lua member_has_any)
    static memberHasAny(member: IMember, server: IServer, permissions: number[]): boolean {
        if (!member || !server || !permissions || permissions.length === 0) {
            return false
        }

        // Accumulate permissions from all roles (matching Lua logic exactly)
        let permInt = 0
        for (const roleId of Object.keys(member.roles || {})) {
            const role = server.roles[roleId]
            if (role && typeof role.permissions === 'number') {
                permInt = permInt | role.permissions
            }
        }

        // Check for owner (matches Lua: member.id == owner)
        if (member.id === server.profile.owner) {
            return true
        }

        // Check for administrator permission (administrator has all permissions)
        if ((permInt & EPermissions.ADMINISTRATOR) === EPermissions.ADMINISTRATOR) {
            return true
        }

        // Check if member has any of the specified permissions
        for (const permission of permissions) {
            if ((permInt & permission) === permission) {
                return true
            }
        }
        return false
    }

    // Check if a member has all of the specified permissions
    static memberHasAll(member: IMember, server: IServer, permissions: number[]): boolean {
        return permissions.every(permission => Permissions.memberHas(member, server, permission))
    }

    // Get all permissions a member has (accumulated from all roles)
    static getMemberPermissions(member: IMember, server: IServer): number {
        if (!member || !server) {
            return 0
        }

        // Server owner has all permissions
        if (member.id === server.profile.owner) {
            return Permissions.maxValue
        }

        // If no roles, return 0
        if (!member.roles || Object.keys(member.roles).length === 0) {
            return 0
        }

        let totalPermissions = 0
        for (const roleId of Object.keys(member.roles)) {
            const role = server.roles[roleId]
            if (role && Permissions.isValid(role.permissions)) {
                totalPermissions = totalPermissions | role.permissions

                // Administrator permission grants all permissions
                if ((role.permissions & EPermissions.ADMINISTRATOR) === EPermissions.ADMINISTRATOR) {
                    return Permissions.maxValue
                }
            }
        }

        return totalPermissions
    }

    // Get the highest role order for a member (matches Lua get_highest_role_order)
    static getHighestRoleOrder(member: IMember, server: IServer): number {
        if (!member || !server) {
            return 0
        }

        let highestOrder = 0
        for (const roleId of Object.keys(member.roles || {})) {
            const role = server.roles[roleId]
            if (role && typeof role.order === 'number' && role.order > highestOrder) {
                highestOrder = role.order
            }
        }
        return highestOrder
    }

    // Check if a permission value has a specific permission
    static hasPermission(permissions: number, permission: number): boolean {
        if (!Permissions.isValid(permissions) || !Permissions.isValid(permission)) {
            return false
        }
        return (permissions & permission) === permission
    }

    // Add a permission to a permission value
    static addPermission(permissions: number, permission: number): number {
        if (!Permissions.isValid(permissions) || !Permissions.isValid(permission)) {
            return permissions
        }
        return permissions | permission
    }

    // Remove a permission from a permission value
    static removePermission(permissions: number, permission: number): number {
        if (!Permissions.isValid(permissions) || !Permissions.isValid(permission)) {
            return permissions
        }
        return permissions & ~permission
    }
}