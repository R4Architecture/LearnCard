import dotenv from 'dotenv';

dotenv.config();

export interface ScalewayEmailAddress {
    email: string;
    name?: string;
}

export interface ScalewayEmailPayload {
    from: ScalewayEmailAddress;
    to: ScalewayEmailAddress[];
    subject: string;
    html?: string;
    text?: string;
}

const SCALEWAY_API_URL = 'https://api.scaleway.com/transactional-email/v1alpha1/regions';

export const sendScalewayEmail = async (payload: ScalewayEmailPayload): Promise<void> => {
    const apiKey = process.env.SCALEWAY_API_KEY;
    const region = process.env.SCALEWAY_REGION || 'fr-par';

    if (!apiKey) {
        console.warn('No SCALEWAY_API_KEY found; email sending disabled.');
        return;
    }

    const response = await fetch(`${SCALEWAY_API_URL}/${region}/emails`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-Auth-Token': apiKey,
        },
        body: JSON.stringify(payload),
    });

    if (!response.ok) {
        const body = await response.text();
        throw new Error(`Scaleway email API error ${response.status}: ${body}`);
    }
};
