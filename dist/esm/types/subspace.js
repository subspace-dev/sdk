// ---------------- Permissions ---------------- //
export var EPermissions;
(function (EPermissions) {
    EPermissions[EPermissions["SEND_MESSAGES"] = 1] = "SEND_MESSAGES";
    EPermissions[EPermissions["MANAGE_NICKNAMES"] = 2] = "MANAGE_NICKNAMES";
    EPermissions[EPermissions["MANAGE_MESSAGES"] = 4] = "MANAGE_MESSAGES";
    EPermissions[EPermissions["KICK_MEMBERS"] = 8] = "KICK_MEMBERS";
    EPermissions[EPermissions["BAN_MEMBERS"] = 16] = "BAN_MEMBERS";
    EPermissions[EPermissions["MANAGE_CHANNELS"] = 32] = "MANAGE_CHANNELS";
    EPermissions[EPermissions["MANAGE_SERVER"] = 64] = "MANAGE_SERVER";
    EPermissions[EPermissions["MANAGE_ROLES"] = 128] = "MANAGE_ROLES";
    EPermissions[EPermissions["MANAGE_MEMBERS"] = 256] = "MANAGE_MEMBERS";
    EPermissions[EPermissions["MENTION_EVERYONE"] = 512] = "MENTION_EVERYONE";
    EPermissions[EPermissions["ADMINISTRATOR"] = 1024] = "ADMINISTRATOR";
    EPermissions[EPermissions["ATTACHMENTS"] = 2048] = "ATTACHMENTS";
    EPermissions[EPermissions["MANAGE_BOTS"] = 4096] = "MANAGE_BOTS";
})(EPermissions || (EPermissions = {}));
