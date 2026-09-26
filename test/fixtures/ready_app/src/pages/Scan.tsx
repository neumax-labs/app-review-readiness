import { Camera, CameraResultType } from '@capacitor/camera';

export async function scanReceipt() {
  return Camera.getPhoto({ resultType: CameraResultType.Uri });
}
