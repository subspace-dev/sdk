/**
 * Validation utilities for Subspace SDK
 * These mirror the validation logic from the Lua backend to provide immediate frontend validation
 */

export class ValidationError extends Error {
    public status: number;

    constructor(status: number, message: string) {
        super(message);
        this.name = 'ValidationError';
        this.status = status;
    }
}

export class SubspaceValidation {
    /**
     * Validates if a string is a valid Arweave transaction ID
     * Must be exactly 43 characters long and contain only alphanumeric, underscore, and dash characters
     */
    static isValidTxId(txid: string | null | undefined): boolean {
        if (!txid || typeof txid !== 'string') return false;
        return txid.length === 43 && /^[A-Za-z0-9_-]+$/.test(txid);
    }

    /**
     * Validates if a string is a valid Arweave transaction ID and throws if not
     */
    static validateTxId(txid: string | null | undefined, fieldName: string): void {
        if (!txid) {
            throw new ValidationError(400, `${fieldName} is required`);
        }
        if (!this.isValidTxId(txid)) {
            throw new ValidationError(400, `${fieldName} must be a valid arweave tx id`);
        }
    }

    /**
     * Validates if a string is a valid Arweave transaction ID (optional field)
     */
    static validateOptionalTxId(txid: string | null | undefined, fieldName: string): void {
        if (txid && !this.isValidTxId(txid)) {
            throw new ValidationError(400, `${fieldName} must be a valid arweave tx id`);
        }
    }

    /**
     * Validates if a value is a non-empty string
     */
    static validateString(value: any, fieldName: string, required: boolean = true): void {
        if (required && (!value || typeof value !== 'string')) {
            throw new ValidationError(400, `${fieldName} is required`);
        }
        if (value && typeof value !== 'string') {
            throw new ValidationError(400, `${fieldName} must be a string`);
        }
    }

    /**
     * Validates if a value is a non-empty string with length constraints
     */
    static validateStringWithLength(
        value: any,
        fieldName: string,
        minLength: number = 1,
        maxLength: number = 2000,
        required: boolean = true
    ): void {
        this.validateString(value, fieldName, required);
        if (value && (value.length < minLength || value.length > maxLength)) {
            throw new ValidationError(400, `${fieldName} must be between ${minLength} and ${maxLength} characters`);
        }
    }

    /**
     * Validates user ID parameter
     */
    static validateUserId(userId: string | null | undefined): void {
        this.validateTxId(userId, "user id");
    }

    /**
     * Validates message ID parameter
     */
    static validateMessageId(messageId: string | null | undefined): void {
        this.validateString(messageId, "message id");
    }

    /**
     * Validates message content
     */
    static validateMessageContent(content: string | null | undefined): void {
        this.validateString(content, "content", true);
    }

    /**
     * Validates bio content (optional)
     */
    static validateBio(bio: string | null | undefined): void {
        if (bio) {
            this.validateString(bio, "bio", false);
        }
    }

    /**
     * Validates profile fields for create/update operations
     */
    static validateProfileFields({ pfp, banner, bio }: {
        pfp?: string | null;
        banner?: string | null;
        bio?: string | null;
    }): void {
        this.validateOptionalTxId(pfp, "pfp");
        this.validateOptionalTxId(banner, "banner");
        this.validateBio(bio);
    }

    /**
     * Validates DM parameters
     */
    static validateDMParams({ userId, content, messageId }: {
        userId?: string | null;
        content?: string | null;
        messageId?: string | null;
    }): void {
        if (userId !== undefined) this.validateUserId(userId);
        if (content !== undefined) this.validateMessageContent(content);
        if (messageId !== undefined) this.validateMessageId(messageId);
    }

    /**
     * Validates friend ID parameter
     */
    static validateFriendId(friendId: string | null | undefined): void {
        this.validateUserId(friendId);
    }

    /**
     * Validates that a user is not trying to friend themselves
     */
    static validateNotSelfFriend(senderId: string, receiverId: string): void {
        if (senderId === receiverId) {
            throw new ValidationError(400, "cannot send friend request to yourself");
        }
    }

    /**
     * Generic validation helper that throws ValidationError
     */
    static assert(condition: boolean, status: number, message: string): void {
        if (!condition) {
            throw new ValidationError(status, message);
        }
    }

    /**
     * Validates required field is present
     */
    static validateRequired(value: any, fieldName: string): void {
        if (value === null || value === undefined || value === '') {
            throw new ValidationError(400, `${fieldName} is required`);
        }
    }

    // #region Server Validation

    /**
     * Validates server creation parameters
     */
    static validateServerCreation({ serverName, serverDescription, serverPfp, serverBanner }: {
        serverName?: string | null;
        serverDescription?: string | null;
        serverPfp?: string | null;
        serverBanner?: string | null;
    }): void {
        this.validateRequired(serverName, "server name");
        this.validateString(serverName, "server name");

        if (serverDescription) {
            this.validateString(serverDescription, "server description", false);
        }

        this.validateOptionalTxId(serverPfp, "server pfp");
        this.validateOptionalTxId(serverBanner, "server banner");
    }

    /**
     * Validates server update parameters
     */
    static validateServerUpdate({ serverName, serverDescription, serverPfp, serverBanner }: {
        serverName?: string | null;
        serverDescription?: string | null;
        serverPfp?: string | null;
        serverBanner?: string | null;
    }): void {
        if (serverName) {
            this.validateString(serverName, "server name", false);
        }

        if (serverDescription) {
            this.validateString(serverDescription, "server description", false);
        }

        this.validateOptionalTxId(serverPfp, "server pfp");
        this.validateOptionalTxId(serverBanner, "server banner");
    }

    /**
     * Validates server ID parameter
     */
    static validateServerId(serverId: string | null | undefined): void {
        this.validateTxId(serverId, "server id");
    }

    /**
     * Validates category parameters
     */
    static validateCategoryParams({ categoryName, categoryOrder }: {
        categoryName?: string | null;
        categoryOrder?: number | null;
    }): void {
        if (categoryName !== undefined) {
            this.validateRequired(categoryName, "category name");
            this.validateString(categoryName, "category name");
        }

        if (categoryOrder !== undefined && categoryOrder !== null) {
            if (typeof categoryOrder !== 'number') {
                throw new ValidationError(400, "category order must be a number");
            }
        }
    }

    /**
     * Validates channel parameters
     */
    static validateChannelParams({ channelName, categoryId, channelOrder, allowMessaging, allowAttachments }: {
        channelName?: string | null;
        categoryId?: string | null;
        channelOrder?: number | null;
        allowMessaging?: number | null;
        allowAttachments?: number | null;
    }): void {
        if (channelName !== undefined) {
            this.validateRequired(channelName, "channel name");
            this.validateString(channelName, "channel name");
        }

        if (categoryId) {
            this.validateString(categoryId, "category id", false);
        }

        if (channelOrder !== undefined && channelOrder !== null) {
            if (typeof channelOrder !== 'number') {
                throw new ValidationError(400, "channel order must be a number");
            }
        }

        if (allowMessaging !== undefined && allowMessaging !== null) {
            if (typeof allowMessaging !== 'number') {
                throw new ValidationError(400, "allow messaging must be a number (0 or 1)");
            }
            if (allowMessaging !== 0 && allowMessaging !== 1) {
                throw new ValidationError(400, "allow messaging must be 0 or 1");
            }
        }

        if (allowAttachments !== undefined && allowAttachments !== null) {
            if (typeof allowAttachments !== 'number') {
                throw new ValidationError(400, "allow attachments must be a number (0 or 1)");
            }
            if (allowAttachments !== 0 && allowAttachments !== 1) {
                throw new ValidationError(400, "allow attachments must be 0 or 1");
            }
        }
    }

    /**
     * Validates hex color format
     */
    static validateHexColor(color: string | null | undefined, fieldName: string): void {
        if (color) {
            this.validateString(color, fieldName, false);
            if (!/^#[0-9A-Fa-f]{6}$/.test(color)) {
                throw new ValidationError(400, `${fieldName} must be a valid hex color (e.g., #FF0000)`);
            }
        }
    }

    /**
     * Validates role parameters
     */
    static validateRoleParams({ roleName, roleColor, rolePermissions, roleOrder, mentionable, hoist }: {
        roleName?: string | null;
        roleColor?: string | null;
        rolePermissions?: number | null;
        roleOrder?: number | null;
        mentionable?: boolean | null;
        hoist?: boolean | null;
    }): void {
        if (roleName !== undefined) {
            this.validateRequired(roleName, "role name");
            this.validateString(roleName, "role name");
        }

        this.validateHexColor(roleColor, "role color");

        if (rolePermissions !== undefined && rolePermissions !== null) {
            if (typeof rolePermissions !== 'number') {
                throw new ValidationError(400, "role permissions must be a number");
            }
            if (rolePermissions < 0) {
                throw new ValidationError(400, "role permissions must be non-negative");
            }
        }

        if (roleOrder !== undefined && roleOrder !== null) {
            if (typeof roleOrder !== 'number') {
                throw new ValidationError(400, "role order must be a number");
            }
        }

        if (mentionable !== undefined && mentionable !== null) {
            if (typeof mentionable !== 'boolean') {
                throw new ValidationError(400, "mentionable must be a boolean");
            }
        }

        if (hoist !== undefined && hoist !== null) {
            if (typeof hoist !== 'boolean') {
                throw new ValidationError(400, "hoist must be a boolean");
            }
        }
    }

    /**
     * Validates role ID parameter
     */
    static validateRoleId(roleId: string | null | undefined): void {
        this.validateRequired(roleId, "role id");
        this.validateString(roleId, "role id");

        if (roleId === "@") {
            throw new ValidationError(400, "cannot modify everyone role");
        }
    }

    /**
     * Validates message sending parameters
     */
    static validateMessageParams({ content, attachments }: {
        content?: string | null;
        attachments?: string[] | null;
    }): void {
        // Must have either content or attachments
        if (!content && (!attachments || attachments.length === 0)) {
            throw new ValidationError(400, "content or attachments required");
        }

        if (content) {
            this.validateString(content, "content", false);
        }

        if (attachments && attachments.length > 0) {
            if (!Array.isArray(attachments)) {
                throw new ValidationError(400, "attachments must be an array");
            }

            if (attachments.length > 10) {
                throw new ValidationError(400, "maximum 10 attachments allowed");
            }

            for (const attachment of attachments) {
                this.validateTxId(attachment, "attachment");
            }
        }
    }

    /**
     * Validates channel ID parameter
     */
    static validateChannelId(channelId: string | null | undefined): void {
        this.validateRequired(channelId, "channel id");
        this.validateString(channelId, "channel id");
    }

    /**
     * Validates category ID parameter
     */
    static validateCategoryId(categoryId: string | null | undefined): void {
        this.validateRequired(categoryId, "category id");
        this.validateString(categoryId, "category id");
    }

    // #endregion
}
