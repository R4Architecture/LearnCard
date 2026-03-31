/**
 * Creates the network consent contract on a self-hosted brain service.
 *
 * Usage:
 *   LCN_URL=https://brain.poc17.eduwallet.nl/trpc node scripts/seed-network-contract.mjs
 *
 * The script prints the contract URI and CONTRACT_OWNER_DID — copy these into
 * your docker-compose build args:
 *   NETWORK_CONSENT_CONTRACT_URI
 *   NETWORK_CONSENT_CONTRACT_OWNER_DID
 */

import { readFileSync } from 'fs';
import { initLearnCard } from '@learncard/init';

const LCN_URL = process.env.LCN_URL;
const CLOUD_URL = process.env.CLOUD_URL;
const SEED = process.env.SEED || 'a'; // must match brain service SEED

if (!LCN_URL) {
    console.error('LCN_URL environment variable is required');
    process.exit(1);
}

const lc = await initLearnCard({
    seed: SEED,
    network: LCN_URL,
    didkit: readFileSync('/app/packages/plugins/didkit/dist/didkit_wasm_bg.wasm'),
    ...(CLOUD_URL ? { cloud: { url: CLOUD_URL } } : {}),
});

// Create a profile for the contract owner if it doesn't exist
try {
    await lc.invoke.createProfile({ profileId: 'learn-cloud', displayName: 'LearnCloud' });
    console.log('Created learn-cloud profile');
} catch (e) {
    const msg = e?.message ?? String(e);
    if (msg.includes('already exists') || msg.includes('Profile already')) {
        console.log('learn-cloud profile already exists');
    } else {
        console.error('Failed to create profile:', msg);
        process.exit(1);
    }
}

const categories = [
    'Achievement', 'ID', 'LearningHistory', 'SkillCredential', 'Badge',
    'CertificateOfCompletion', 'LicenseAndCertification', 'MilitaryVerification',
    'OpenBadge', 'EmploymentHistory', 'EducationHistory', 'VerifiableCredential',
];

const contractUri = await lc.invoke.createContract({
    name: 'LearnCard Network Consent',
    description: 'Consent contract for sharing credentials with the LearnCard Network',
    contract: {
        read: {
            personal: { name: { required: false } },
            credentials: {
                categories: Object.fromEntries(
                    categories.map(c => [c, { required: false }])
                ),
            },
        },
        write: {
            credentials: {
                categories: Object.fromEntries(
                    categories.map(c => [c, { required: false }])
                ),
            },
        },
    },
});

const did = lc.id.did();

console.log('\n✅ Contract created successfully!\n');
console.log('Add these to your docker-compose build args and env vars:\n');
console.log(`NETWORK_CONSENT_CONTRACT_URI=${contractUri}`);
console.log(`NETWORK_CONSENT_CONTRACT_OWNER_DID=${did}`);
