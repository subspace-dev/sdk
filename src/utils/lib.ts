import { connect } from "@permaweb/aoconnect"
import { ARIO } from "@ar.io/sdk"

export type WanderTierInfo = {
    balance: string;
    progress: number;
    rank: number;
    snapshotTimestamp: number;
    tier: number;
    totalHolders: number;
}

export async function getPrimaryName(address: string): Promise<string> {
    const ario = ARIO.mainnet()
    const res = await ario.getPrimaryName({ address })
    return res.name
}

export async function getWanderTierInfo(walletAddress: string): Promise<WanderTierInfo | null> {
    try {
        const defaultCuUrl = "https://cu.arnode.asia"
        const cuUrl = localStorage ? localStorage.getItem("subspace-cu-url") || defaultCuUrl : defaultCuUrl
        const ao = connect({ MODE: "legacy", CU_URL: cuUrl })
        const dryrunRes = await ao.dryrun({
            Owner: walletAddress,
            process: "rkAezEIgacJZ_dVuZHOKJR8WKpSDqLGfgPJrs_Es7CA",
            tags: [{ name: "Action", value: "Get-Wallet-Info" }],
        });

        const message = dryrunRes.Messages?.[0];

        // Add a dropdown for dryrunRes for debugging
        if (!message?.Data) {
            if (typeof window !== "undefined") {
                // Create a details/summary dropdown in the console for dryrunRes
                // This is a nice way to inspect the dryrunRes object interactively
                // @ts-ignore
                if (console.groupCollapsed && console.dir) {
                    console.groupCollapsed(`No wander tier data returned for wallet: ${walletAddress} (show dryrunRes)`);
                    console.dir(dryrunRes);
                    console.groupEnd();
                } else {
                    console.warn(`No wander tier data returned for wallet: ${walletAddress}`);
                    console.log("dryrunRes:", dryrunRes);
                }
            } else {
                // Fallback for non-browser environments
                console.warn(`No wander tier data returned for wallet: ${walletAddress}`);
                console.log("dryrunRes:", dryrunRes);
            }
            return null;
        }

        let data;
        try {
            data = JSON.parse(message.Data);
        } catch (parseError) {
            console.warn(`Failed to parse tier data for wallet: ${walletAddress}`, parseError);
            return null;
        }

        if (data?.tier === undefined || data?.tier === null) {
            console.warn(`No tier data found for wallet: ${walletAddress}`);
            return null;
        }

        const tierInfo: WanderTierInfo = { ...data };
        return tierInfo;
    } catch (error) {
        console.warn(`Failed to fetch tier info for wallet: ${walletAddress}`, error);
        return null;
    }
}