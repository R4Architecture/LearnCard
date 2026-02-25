export const FIREBASE_REDIRECT_URL ='frontend.local';

export const WEB3AUTH_NATIVE_CONFIG = {
    // changed for eduCredentials
    clientId:
        'BBB5ReobO60-BI4pfLcbIIaVSRIAq7NXoI0CJAtsoLxqOdn-xmuOQM_wHK_tA6Qm_GvspdO9rC-a4jfuN7zoC-zjJWLAPGWKzrQ',
    network: 'testnet',

    verifierClientId: '776298253175-kkf562eofl541vu0oedfdvrk40bpkbh7.apps.googleusercontent.com',
    verifierName: 'educredentials-firebase',
    verifierId: 'educredentials-firebase',
    verifierTypeOfLogin: 'jwt',

    whiteLabelName: 'LearnCard',
    whiteLabelLogoLight:
        'https://cdn.filestackcontent.com/rotate=deg:exif/auto_image/tRrHF9W2Q9ugaiIAAJI8',
    whiteLabelLogoDark:
        'https://cdn.filestackcontent.com/rotate=deg:exif/auto_image/tRrHF9W2Q9ugaiIAAJI8',
    whiteLabelDark: false,
    whiteLabelPrimaryColor: '#20c397',

    loginProvider: 'jwt',
    loginDomain: `https://${FIREBASE_REDIRECT_URL}`,

    loginVerifierIdField: 'sub',
    // loginIdToken: idToken,
};
