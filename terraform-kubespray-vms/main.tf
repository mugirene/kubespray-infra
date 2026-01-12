resource "null_resource" "connect_iso" {
  for_each = vsphere_virtual_machine.k8s

  depends_on = [vsphere_virtual_machine.k8s]

  triggers = {
    vm_name = each.value.name
    iso     = var.ubuntu_iso_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]

    command = <<-EOT
      set -eu

      export GOVC_URL="https://${var.vsphere_server}"
      export GOVC_USERNAME="${var.vsphere_user}"
      export GOVC_PASSWORD="${var.vsphere_password}"
      export GOVC_INSECURE=1
      export GOVC_DATACENTER="${var.datacenter}"

      VM="${each.value.name}"
      DS="${var.datastore}"
      ISO_REL="ISO/ubuntu-24.04.3-live-server-amd64.iso"

      echo "===== [govc] Working on VM: $VM ====="
      govc vm.info "$VM" | grep -i "Power state" || true

      echo "[govc] Ensure VM is powered on..."
      govc vm.power -on "$VM" || true
      sleep 2

      echo "[govc] List CDROM devices:"
      govc device.ls -vm "$VM" | grep -i cdrom || true

      CDROM_DEV="$(govc device.ls -vm "$VM" | awk '/cdrom/ {print $1; exit}')"
      if [ -z "$CDROM_DEV" ]; then
        echo "[govc] ERROR: No CDROM device found for $VM"
        govc device.ls -vm "$VM"
        exit 1
      fi
      echo "[govc] Using CDROM device: $CDROM_DEV"

      echo "[govc] Insert ISO backing (datastore=$DS, iso=$ISO_REL)"
      govc device.cdrom.insert -vm "$VM" -ds "$DS" "$CDROM_DEV" "$ISO_REL"

      echo "[govc] Connect CDROM device"
      govc device.connect -vm "$VM" "$CDROM_DEV"

      echo "[govc] (Optional) Connect NIC as well"
      NIC_DEV="$(govc device.ls -vm "$VM" | awk '/ethernet/ {print $1; exit}')"
      if [ -n "$NIC_DEV" ]; then
        govc device.connect -vm "$VM" "$NIC_DEV" || true
      fi

      echo "[govc] Verify CDROM state:"
      govc device.info -vm "$VM" "$CDROM_DEV" | egrep 'Connected:|Start connected:|Status:|Summary:'

      echo "[govc] Power-cycle $VM to force BIOS to see CDROM"
      govc vm.power -off "$VM" || true
      sleep 2
      govc vm.power -on "$VM" || true

      echo "===== [govc] Done: $VM ====="
    EOT
  }
}

