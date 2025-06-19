import { SubspaceConfigReadOnly, SubspaceConfig } from './types/inputs';
import { SubspaceClient, SubspaceClientReadOnly } from './subspace';
export declare class Subspace {
    static init(): SubspaceClientReadOnly;
    static init(params: SubspaceConfigReadOnly): SubspaceClientReadOnly;
    static init(params: SubspaceConfig): SubspaceClient;
}
