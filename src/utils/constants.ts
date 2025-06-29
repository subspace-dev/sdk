export const Constants = {
    Subspace: 'ZrIAe6d6waj7ClOtDgOVH5XFSruDL8u3yCG6lrKYS68',

    Actions: {
        // Profile actions
        GetProfile: 'Get-Profile',
        GetBulkProfile: 'Get-Bulk-Profile',
        CreateProfile: 'Create-Profile',
        UpdateProfile: 'Update-Profile',
        GetOriginalId: 'Get-Original-Id',
        GetNotifications: 'Get-Notifications',
        JoinServer: 'Join-Server',
        LeaveServer: 'Leave-Server',

        // Friend actions
        SendFriendRequest: 'Add-Friend',
        AcceptFriendRequest: 'Accept-Friend',
        RejectFriendRequest: 'Reject-Friend',
        RemoveFriend: 'Remove-Friend',

        // Direct Message actions
        GetDMs: 'Get-DMs',
        SendDM: 'Send-DM',
        EditDM: 'Edit-DM',
        DeleteDM: 'Delete-DM',

        // Server actions
        Info: 'Info',
        Balance: 'Balance',
        Balances: 'Balances',
        TotalSupply: 'Total-Supply',
        AnchorToServer: 'Anchor-To-Server',
        GetServer: 'Get-Server',
        CreateServer: 'Create-Server',
        UpdateServer: 'Update-Server',

        // Member actions
        GetMember: 'Get-Member',
        GetAllMembers: 'Get-All-Members',
        UpdateMember: 'Update-Member',
        KickMember: 'Kick-Member',
        BanMember: 'Ban-Member',
        UnbanMember: 'Unban-Member',

        // Message actions
        GetSingleMessage: 'Get-Single-Message',
        GetMessages: 'Get-Messages',
        SendMessage: 'Send-Message',
        EditMessage: 'Edit-Message',
        DeleteMessage: 'Delete-Message',

        // Category actions
        CreateCategory: 'Create-Category',
        UpdateCategory: 'Update-Category',
        DeleteCategory: 'Delete-Category',

        // Channel actions
        CreateChannel: 'Create-Channel',
        UpdateChannel: 'Update-Channel',
        DeleteChannel: 'Delete-Channel',

        // Role actions
        CreateRole: 'Create-Role',
        UpdateRole: 'Update-Role',
        DeleteRole: 'Delete-Role',
        AssignRole: 'Assign-Role',
        UnassignRole: 'Unassign-Role',

        // Delegation actions
        AddDelegation: 'Add-Delegation',
        RemoveDelegation: 'Remove-Delegation',
        RemoveAllDelegations: 'Remove-All-Delegations',

        // Bot actions
        CreateBot: 'Create-Bot',
        AnchorToBot: 'Anchor-To-Bot',
        BotInfo: 'Bot-Info',
        AddBot: 'Add-Bot',
        ApproveAddBot: 'Approve-Add-Bot',
        Subscribe: 'Subscribe',
        RemoveBot: 'Remove-Bot',
    }
}