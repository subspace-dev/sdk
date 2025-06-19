import { SubspaceClient, SubspaceClientReadOnly } from './subspace';
export class Subspace {
    static init(params) {
        if (!params) {
            return new SubspaceClientReadOnly({});
        }
        if ('signer' in params) {
            return new SubspaceClient(params);
        }
        return new SubspaceClientReadOnly(params);
    }
}
