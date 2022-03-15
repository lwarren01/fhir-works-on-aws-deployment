import _ from 'lodash';
import dynamodb from './dynamodb';

const DEFAULT_IMAGE = {
    id: {
        S: 'acdd2370-db4b-43d7-92de-e2e82ebef362',
    },
    vid: {
        N: '2',
    },
    resourceType: {
        S: 'Patient',
    },
    address: {
        L: [
            {
                city: {
                    S: 'Halifax',
                },
            },
            {
                city: {
                    S: 'Toronto',
                },
            },
        ],
    },
};

function generateImage(): any {
    return _.cloneDeep(DEFAULT_IMAGE);
}

function generateImageWithTTL(ttl: number): any {
    const image = generateImage();
    image[dynamodb.TTL_FIELD_NAME] = ttl;
    return image;
}

function generateImageWithCity(cities: string[]): any {
    const image = generateImage();
    image.address.L = cities.map((city) => {
        return {
            city: {
                S: city,
            },
        };
    });
    return image;
}

export default {
    generateImage,
    generateImageWithTTL,
    generateImageWithCity,
};
