/*
 *  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *  SPDX-License-Identifier: Apache-2.0
 */

import { CorsOptions } from 'cors';
import serverless from 'serverless-http';
import { generateServerlessRouter } from 'fhir-works-on-aws-routing';
import { getFhirConfig, genericResources } from './config';

require('console-stamp')(console, {
    format: ':date(yyyy/mm/dd HH:MM:ss.l)',
});

const corsOptions: CorsOptions = {
    origin: [
        'http://localhost:8000',
        'http://localhost:9000',
        'https://fhir.fhir-zone-dev.dht.live',
        'https://fhir.atom-sbx.dht.live',
    ],
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['x-api-key', 'authorization'],
    credentials: true,
    maxAge: 3600,
};

const ensureAsyncInit = async (initPromise: Promise<any>): Promise<void> => {
    try {
        await initPromise;
    } catch (e) {
        console.error('Async initialization failed', e);
        // Explicitly exit the process so that next invocation re-runs the init code.
        // This prevents Lambda containers from caching a rejected init promise
        process.exit(1);
    }
};

async function asyncServerless() {
    return serverless(generateServerlessRouter(await getFhirConfig(), genericResources, corsOptions), {
        request(request: any, event: any) {
            request.user = event.user;
        },
    });
}

console.log('start: asyncServerless()');
const serverlessHandler: Promise<any> = asyncServerless();
console.log('end: asyncServerless()');

exports.handler = async (event: any = {}, context: any = {}): Promise<any> => {
    console.log('start: asyncServerless()');
    await ensureAsyncInit(serverlessHandler);
    console.log('end: asyncServerless()');

    return (await serverlessHandler)(event, context);
};
