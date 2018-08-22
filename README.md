# land
Contracts for Land

# LandInfo生成规则
encodeTokenIdForInfo(x, y) + (goldRate << 48) + (woodRate << 64) + (waterRate << 80) + (fireRate << 96) + (soilRate << 112) + (isReserved << 128) + (isSpecial << 129) + (hasBox << 130)


# LandData部署
前置准备：部署`market-contracts/contracts/auction/RewardBox`合约
