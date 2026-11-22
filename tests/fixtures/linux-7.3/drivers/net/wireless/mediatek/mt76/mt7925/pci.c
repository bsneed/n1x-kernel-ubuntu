/* SPDX-License-Identifier: BSD-3-Clause-Clear */
/* Excerpt of linux-7.3 drivers/net/wireless/mediatek/mt76/mt7925/pci.c, lines 486-529, for tests/t-patch.sh. */

static const struct mt792x_irq_map mt7925_irq_map = {
	.host_irq_enable = MT_WFDMA0_HOST_INT_ENA,
	.tx = {
		.all_complete_mask = MT_INT_TX_DONE_ALL,
		.mcu_complete_mask = MT_INT_TX_DONE_MCU,
	},
	.rx = {
		.all_complete_mask = MT7925_INT_RX_DONE_ALL,
		.data_complete_mask = MT7925_INT_RX_DONE_DATA,
		.wm_complete_mask = MT7925_INT_RX_DONE_WM,
		.wm2_complete_mask = MT_INT_RX_DONE_WM2,
	},
};

static const struct mt792x_irq_map mt7927_irq_map = {
	.host_irq_enable = MT_WFDMA0_HOST_INT_ENA,
	.tx = {
		.all_complete_mask = MT_INT_TX_DONE_ALL,
		.mcu_complete_mask = MT_INT_TX_DONE_MCU,
	},
	.rx = {
		.all_complete_mask = MT7927_INT_RX_DONE_ALL,
		.data_complete_mask = MT7927_INT_RX_DONE_DATA,
		.wm_complete_mask = MT7927_INT_RX_DONE_WM,
		.wm2_complete_mask = MT7927_INT_RX_DONE_WM2,
	},
};

static const struct mt792x_irq_map mt7928_irq_map = {
	.host_irq_enable = MT_WFDMA0_HOST_INT_ENA,
	.tx = {
		.all_complete_mask = MT_INT_TX_DONE_ALL,
		.mcu_complete_mask = MT_INT_TX_DONE_MCU,
	},
	.rx = {
		.all_complete_mask = MT7928_INT_RX_DONE_ALL,
		.data_complete_mask = MT7928_INT_RX_DONE_DATA,
		.wm_complete_mask = MT7928_INT_RX_DONE_WM,
		.wm2_complete_mask = MT_INT_RX_DONE_WM2,
	},
};

static int mt7925_pci_probe(struct pci_dev *pdev,
			    const struct pci_device_id *id)
