import { readFileSync } from 'node:fs';

export const apiSchema = JSON.parse(readFileSync(
  new URL('../../../../packages/contracts/openapi/api-v1.schema.json', import.meta.url), 'utf8',
));
export function contract(name: string) { return { $ref: `urn:duoscene:api:v1#/definitions/${name}` }; }
export function responseContract(name: string) {
  return {
    type: 'object', additionalProperties: false, required: ['data', 'requestId'],
    properties: { data: contract(name), requestId: { type: 'string' } },
  };
}
