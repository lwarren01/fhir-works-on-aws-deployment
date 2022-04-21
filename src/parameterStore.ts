import AWS from 'aws-sdk';

const { IS_OFFLINE } = process.env;

const localStackEndPoint = {
    region: 'us-east-1',
    endpoint: new AWS.Endpoint('http://localhost:4566'),
    sslEnabled: false,
    accessKeyId: 'test',
    secretAccessKey: 'test',
};

const parameterStore = IS_OFFLINE ? new AWS.SSM(localStackEndPoint) : new AWS.SSM();

export default async function getParameter(parameterName: string): Promise<string> {
    try {
        const result = await parameterStore
            .getParameter({
                Name: parameterName,
            })
            .promise();
        return result.Parameter!.Value!;
    } catch (err) {
        console.error('ParameterStore error:', err);
        throw err;
    }
}
