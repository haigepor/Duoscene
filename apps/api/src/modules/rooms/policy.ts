import { ApiError } from '../../shared/errors.ts';

export function nextSeat(occupied: number[]): 1 | 2 {
  if (!occupied.includes(1)) return 1;
  if (!occupied.includes(2)) return 2;
  throw new ApiError(409, 'ROOM_FULL', 'ROOM_FULL: room already has two members');
}

export function assertOwnerMayLeave(ownerId: string, userId: string) {
  if (ownerId === userId) {
    throw new ApiError(409, 'OWNER_MUST_CLOSE', 'OWNER_MUST_CLOSE: owner must close the room before leaving');
  }
}
