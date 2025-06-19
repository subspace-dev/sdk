import { SubspaceConfigReadOnly, SubspaceConfig } from './types/inputs'
import { SubspaceClient, SubspaceClientReadOnly } from './subspace';
import { AoClient } from './types/ao';
import { connect } from '@permaweb/aoconnect';

export class Subspace {
    static init(): SubspaceClientReadOnly
    static init(params: SubspaceConfigReadOnly): SubspaceClientReadOnly
    static init(params: SubspaceConfig): SubspaceClient

    static init(params?: SubspaceConfigReadOnly | SubspaceConfig): SubspaceClientReadOnly | SubspaceClient {
        if (!params) {
            return new SubspaceClientReadOnly({});
        }
        if ('signer' in params) {
            return new SubspaceClient(params);
        }
        return new SubspaceClientReadOnly(params);
    }
}

// Export all types and interfaces for external use
export * from './types/subspace';
export * from './types/inputs';
export * from './types/ao';
export * from './types/responses';

// Export main classes
export { SubspaceClient, SubspaceClientReadOnly } from './subspace';
export { Profile } from './profile';
export { Server, ServerReadOnly } from './server';
export { Bot } from './bot';