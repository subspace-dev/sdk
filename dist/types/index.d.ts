import { SubspaceConfigReadOnly, SubspaceConfig } from './types/inputs';
import { SubspaceClient, SubspaceClientReadOnly } from './subspace';
export declare class Subspace {
    static init(): SubspaceClientReadOnly;
    static init(params: SubspaceConfigReadOnly): SubspaceClientReadOnly;
    static init(params: SubspaceConfig): SubspaceClient;
}
export * from './types/subspace';
export * from './types/inputs';
export * from './types/ao';
export * from './types/responses';
export { SubspaceClient, SubspaceClientReadOnly } from './subspace';
export { Profile } from './profile';
export { Server, ServerReadOnly } from './server';
export { Bot } from './bot';
