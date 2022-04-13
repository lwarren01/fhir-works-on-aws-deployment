import AWS from 'aws-sdk';

const parameterStore = new AWS.SSM();

export default async function getParameter(parameterName: string): Promise<string> {
    let result;
    try {
        console.log(`start: getParameter(${parameterName})`);
        result = await parameterStore
            .getParameter({
                Name: parameterName,
            })
            .promise();
        console.log(`end: getParameter(${parameterName})`);
    } catch (err) {
        console.error('ParameterStore error:', err);
        throw err;
    }
    const parameterValue = result.Parameter!.Value!;

    return parameterValue;
}
