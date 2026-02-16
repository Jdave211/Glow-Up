interface AppleAuthResponse {
    success: boolean;
    user?: any;
    token?: string;
    error?: string;
}
export declare function verifyAppleToken(identityToken: string, fullName?: {
    givenName?: string;
    familyName?: string;
}): Promise<AppleAuthResponse>;
export {};
//# sourceMappingURL=apple.d.ts.map