"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Subspace = void 0;
const subspace_1 = require("./subspace");
class Subspace {
    static init(params) {
        if (!params) {
            return new subspace_1.SubspaceClientReadOnly({});
        }
        if ('signer' in params) {
            return new subspace_1.SubspaceClient(params);
        }
        return new subspace_1.SubspaceClientReadOnly(params);
    }
}
exports.Subspace = Subspace;
