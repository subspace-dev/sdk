# Subspace SDK

A TypeScript client library for the **Subspace** decentralized chat platform built on [AO (Arweave Operating System)](https://ao.arweave.dev/). Subspace provides a Discord-like experience with servers, channels, direct messaging, bots, and more - all running on a decentralized, permanent infrastructure.

## Installation

```bash
npm install @subspace-chat/sdk
```

## Quick Start

### Initialize the Client

```typescript
import { SubspaceClient } from '@subspace-chat/sdk';

// Read-only client (no wallet required)
const readOnlyClient = new SubspaceClientReadOnly({
  CU_URL: "https://cu.arnode.asia",
  GATEWAY_URL: "https://arnode.asia"
});

// Full client with wallet (for write operations)
const client = new SubspaceClient({
  signer: yourAoSigner // AO wallet signer
});
```

### Profile Management

```typescript
// Create a profile
const profile = await client.createProfile();

// Get a profile
const userProfile = await client.getProfile("user-id");

// Update profile
await profile.updateProfile({
  Pfp: "arweave-transaction-id-of-profile-picture"
});
```

### Server Operations

```typescript
// Create a server
const server = await client.createServer({
  name: "My Server",
  logo: "arweave-transaction-id-of-logo"
});

// Get server info
const serverInfo = await client.getServer("server-id");

// Create a category
await server.createCategory({
  name: "General",
  allowMessaging: true,
  allowAttachments: true
});

// Create a channel
await server.createChannel({
  name: "general-chat",
  categoryId: "category-id",
  allowMessaging: true
});

// Send a message
await server.sendMessage({
  channelId: "channel-id",
  content: "Hello, Subspace!",
  attachments: ["file-hash-1", "file-hash-2"]
});
```

### Friend System & Direct Messages

```typescript
// Send friend request
await profile.sendFriendRequest("friend-user-id");

// Accept friend request
await profile.acceptFriendRequest("sender-user-id");

// Send direct message
await profile.sendDM({
  friendId: "friend-user-id",
  content: "Hey there!",
  replyTo: "message-id" // optional
});

// Get DM history
const dmHistory = await profile.getDMs({
  friendId: "friend-user-id",
  limit: 50
});
```

### Bot Management

```typescript
// Create a bot
const bot = await client.createBot({
  botName: "My Bot",
  botPfp: "arweave-transaction-id",
  publicBot: true
});

// Add bot to server
await client.addBot({
  botProcess: bot.botProcess,
  serverId: "server-id"
});
```

### Role & Permission Management

```typescript
// Create a role
await server.createRole({
  name: "Moderator",
  color: "#ff6b6b",
  permissions: EPermissions.MANAGE_MESSAGES | EPermissions.KICK_MEMBERS
});

// Assign role to user
await server.assignRole({
  targetUserId: "user-id",
  roleId: "role-id"
});
```

## API Reference

### SubspaceClient

The main client class for interacting with Subspace.

#### Methods

- `getProfile(userId?: string)` - Get user profile
- `getBulkProfile(userIds: string[])` - Get multiple profiles
- `createProfile()` - Create a new profile
- `createServer(params)` - Create a new server
- `getServer(serverId)` - Get server information
- `createBot(params)` - Create a new bot
- `addBot(params)` - Add bot to server
- `removeBot(params)` - Remove bot from server

### Profile

Represents a user profile with social features.

#### Methods

- `updateProfile(params)` - Update profile information
- `sendFriendRequest(userId)` - Send friend request
- `acceptFriendRequest(userId)` - Accept friend request
- `rejectFriendRequest(userId)` - Reject friend request
- `removeFriend(userId)` - Remove friend
- `sendDM(params)` - Send direct message
- `editDM(params)` - Edit direct message
- `deleteDM(params)` - Delete direct message
- `getDMs(params)` - Get DM history

### Server

Represents a chat server with channels, roles, and members.

#### Methods

- `getMember(userId)` - Get server member info
- `getAllMembers()` - Get all server members
- `createCategory(params)` - Create message category
- `createChannel(params)` - Create chat channel
- `createRole(params)` - Create permission role
- `assignRole(params)` - Assign role to member
- `sendMessage(params)` - Send message to channel
- `editMessage(params)` - Edit channel message
- `deleteMessage(messageId)` - Delete message
- `getMessages(params)` - Get channel messages
- `kickMember(userId)` - Kick server member
- `banMember(userId)` - Ban server member

### Bot

Represents an automated bot that can join servers.

#### Properties

- `botProcess` - AO process ID of the bot
- `botName` - Display name of the bot
- `botPfp` - Profile picture transaction ID
- `botPublic` - Whether bot is publicly discoverable
- `userId` - Owner's user ID

## Permissions

The permission system uses bitwise flags for granular access control:

```typescript
export enum EPermissions {
  SEND_MESSAGES = 1,      // Send messages in channels
  MANAGE_NICKNAMES = 2,   // Change member nicknames
  MANAGE_MESSAGES = 4,    // Edit/delete others' messages
  KICK_MEMBERS = 8,       // Kick members from server
  BAN_MEMBERS = 16,       // Ban members from server
  MANAGE_CHANNELS = 32,   // Create/edit channels and categories
  MANAGE_SERVER = 64,     // Edit server settings
  MANAGE_ROLES = 128,     // Create/edit roles
  MANAGE_MEMBERS = 256,   // Manage member roles and permissions
  MENTION_EVERYONE = 512, // Use @everyone mentions
  ADMINISTRATOR = 1024,   // Full administrator access
  ATTACHMENTS = 2048,     // Send file attachments
  MANAGE_BOTS = 4096      // Add/remove bots
}
```

Combine permissions using bitwise OR:

```typescript
const moderatorPerms = EPermissions.MANAGE_MESSAGES | EPermissions.KICK_MEMBERS;
```

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/ankushKun/subspace-sdk.git
cd subspace-sdk

# Install dependencies
npm install

# Build the project
npm run build

# Development with watch mode
npm run dev
```

### Building

```bash
# Clean build
npm run clean

# Build ES modules and CommonJS
npm run build

# Build only ES modules
npm run build:esm

# Build only CommonJS
npm run build:cjs

# Type checking
npm run typecheck
```

### Project Structure

```
src/
├── index.ts          # Main export file
├── subspace.ts       # Main client classes
├── profile.ts        # Profile management
├── server.ts         # Server operations
├── bot.ts           # Bot functionality
├── types/           # TypeScript definitions
│   ├── ao.d.ts      # AO-specific types
│   ├── inputs.d.ts  # Input parameter types
│   ├── subspace.d.ts # Main interface definitions
│   └── responses.d.ts # Response types
└── utilts/          # Utility functions
    ├── ao.ts        # AO interaction helpers
    └── constants.ts # Action constants
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- [AO Documentation](https://ao.arweave.dev/)
- [Arweave](https://arweave.org/)

- [Subspace app](https://subspace.ar.io)
- [npm Package](https://www.npmjs.com/package/@subspace-chat/sdk)

## Support

For questions, issues, or contributions, please visit our [GitHub Issues](https://github.com/ankushKun/subspace-sdk/issues) page.

---

Built with ❤️ for the decentralized future
