exports.handler = (event, context, callback) => {
  try {
    event.queryStringParameters.authToken === "ce3fbe32cfd6a36903fabb660ab164ceda569860d54a38e48c5701f22cddcf72"
      ? callback(null, { principalId: 'user', policyDocument:
          { Version: '2012-10-17', Statement: [{ Action: 'execute-api:Invoke', Effect: 'Allow', Resource: event.methodArn }] } })
      : callback('Unauthorized');
  } catch (e) {
    console.error('Error verifying auth token:', e);
    callback('Unauthorized due to unexpected error');
  }
};
