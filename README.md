# Subspace SDK

A modular TypeScript SDK for interacting with the Subspace protocol on Arweave.

## Installation

```bash
npm install @subspace-protocol/sdk
```

## Quick Start

```typescript
import { Subspace } from '@subspace-protocol/sdk';

// Initialize the SDK
const subspace = new Subspace({
    CU_URL: 'https://cu.arnode.asia',
    GATEWAY_URL: 'https://arweave.net',
    owner: 'your-wallet-address',
    signer: yourAoSigner, // Optional: for write operations
    // jwk: yourJWK,      // Alternative: provide JWK for signing
});

// Use the modular managers
const profile = await subspace.user.getProfile('user-id');
const server = await subspace.server.getServer('server-id');
const messages = await subspace.server.getMessages('server-id', {
    channelId: 'channel-id',
    limit: 50
});
```

## Architecture

The SDK is built with a modular architecture:

### Core Components

- **`Subspace`**: Main class that coordinates all managers
- **`ConnectionManager`**: Handles AO connections and communication
- **Domain Managers**: Specialized managers for different functionality areas

### Domain Managers

#### User Manager (`subspace.user`)
Handles user profiles, friends, direct messages, and user actions.

```typescript
// Profile operations
const profile = await subspace.user.getProfile('user-id');
const profiles = await subspace.user.getBulkProfiles(['user1', 'user2']);
await subspace.user.updateProfile({ pfp: 'new-pfp-url' });

// Friend operations
await subspace.user.sendFriendRequest('friend-id');
await subspace.user.acceptFriendRequest('friend-id');

// Server operations
await subspace.user.joinServer('server-id');
await subspace.user.leaveServer('server-id');

// Direct messages
const dms = await subspace.user.getDMs('dm-process-id', { limit: 50 });
await subspace.user.sendDM('dm-process-id', { content: 'Hello!' });
```

#### Server Manager (`subspace.server`)
Handles server operations, channels, categories, roles, and messages.

```typescript
// Server operations
const server = await subspace.server.getServer('server-id');
const serverId = await subspace.server.createServer({
    name: 'My Server',
    logo: 'logo-url',
    description: 'Server description'
});

// Member operations
const members = await subspace.server.getAllMembers('server-id');
const member = await subspace.server.getMember('server-id', 'user-id');
await subspace.server.updateMember('server-id', {
    userId: 'user-id',
    nickname: 'New Nickname'
});

// Channel operations
await subspace.server.createChannel('server-id', {
    name: 'general',
    categoryId: 'category-id',
    type: 'text'
});

// Message operations
const messages = await subspace.server.getMessages('server-id', {
    channelId: 'channel-id',
    limit: 50
});
await subspace.server.sendMessage('server-id', {
    channelId: 'channel-id',
    content: 'Hello, world!'
});
```

#### Bot Manager (`subspace.bot`)
Handles bot creation, management, and deployment.

```typescript
// Bot operations
const botId = await subspace.bot.createBot({
    name: 'My Bot',
    description: 'A helpful bot',
    source: 'bot-source-code'
});

const bot = await subspace.bot.getBot('bot-id');
await subspace.bot.addBotToServer({
    serverId: 'server-id',
    botId: 'bot-id'
});
```

## Configuration

### Connection Configuration

```typescript
interface ConnectionConfig {
    CU_URL?: string;          // Compute Unit URL
    GATEWAY_URL?: string;     // Arweave Gateway URL
    signer?: AoSigner;        // AO Signer for transactions
    jwk?: JWKInterface;       // JWK for signing
    owner?: string;           // Owner address
}
```

### Advanced Usage

```typescript
// Update configuration
subspace.updateConfig({
    CU_URL: 'https://cu.ardrive.io'
});

// Switch compute unit
subspace.switchCu();

// Get connection info
const info = subspace.getConnectionInfo();
console.log(info.cuUrl, info.hasJwk, info.hasSigner);

// Use managers independently
import { UserManager, ServerManager, ConnectionManager } from '@subspace-protocol/sdk';

const connectionManager = new ConnectionManager({
    CU_URL: 'https://cu.arnode.asia'
});
const userManager = new UserManager(connectionManager);
const serverManager = new ServerManager(connectionManager);
```

## Types

The SDK exports comprehensive TypeScript types:

```typescript
import type {
    // Core types
    Subspace,
    ConnectionConfig,
    Tag,
    MessageResult,
    AoSigner,
    
    // User types
    Profile,
    Notification,
    Friend,
    DMMessage,
    DMResponse,
    
    // Server types
    Server,
    Member,
    Channel,
    Category,
    Role,
    Message,
    MessagesResponse,
    
    // Bot types
    Bot,
    BotInfo
} from '@subspace-protocol/sdk';
```

## Error Handling

The SDK provides comprehensive error handling:

```typescript
try {
    const profile = await subspace.user.getProfile('user-id');
} catch (error) {
    if (error.message.includes('No signer available')) {
        console.error('Signer required for this operation');
    } else {
        console.error('Failed to get profile:', error);
    }
}
```

## Migration from Legacy SDK

If you're migrating from the legacy SDK, here are the key changes:

### Before (Legacy)
```typescript
// Static methods
const profile = await Subspace.getProfile('user-id');
const server = await Subspace.getServer('server-id');
await Subspace.sendMessage(serverId, { content: 'Hello' });
```

### After (New SDK)
```typescript
// Instance methods with managers
const subspace = new Subspace(config);
const profile = await subspace.user.getProfile('user-id');
const server = await subspace.server.getServer('server-id');
await subspace.server.sendMessage(serverId, { content: 'Hello' });
```

## Development

```bash
# Install dependencies
npm install

# Build the SDK
npm run build

# Run tests
npm test

# Start development mode
npm run dev
```

## License

MIT License - see LICENSE file for details.
