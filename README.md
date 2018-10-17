# land
Contracts for Land

# 地块资源释放速率编码方式
```python
resourceRate = goldRate + woodRate << 16 + waterRate << 32 + fireRate << 48 + soilRate << 64
```

# 生成新地块
LandBase.assignNewLand(...)

# 拍卖相关
## 创建拍卖
ObjectOwnership.approveAndCall(...)

# Addresses On Kovan
```bash
LocationCoder: 0x1ad88b7bd8373f36f811fbee004a872dd3ead4fd
ObjectOwnershipAuthority: 0xdfa16a52dbcd9bbf7be96ea2878a150d44ced5ff
TokenLocationAuthority: 0x7feaf7dee2aacbb7c46af61fe4a415d632b1acc3
gold: 0x0d0476c2d6b03d911f6dd11fb59bf4232405fb7b
wood: 0x522f9ab825eadac76bb331bd9794130359190e3a
water: 0x18573bba101ab51c98237da0c07f3e0ccd622335
fire: 0x1141253e4ccdd8516f104e6e277ceb71f85a9c49
soil: 0xa2deed90de260efccd1ef56fe7a7507909aaf3b4
SettingIds: 0x7bd5b8d5a5628b4300c069abbc2b23b6098e9eea
SettingsRegistry: 0xf21930682df28044d88623e0707facf419477041

TokenLocation: 0x3c12e1e65d89098589103ae8412adeead7285ff3
TokenLocationProxy: 0x160201d1f289e2ab8110c604be3bc54b98e1c931

LandBase: 0x616ac61021e16bfb69bc6fdb7ff5919a6bbd1d55
LandBaseProxy: 0x342a453e3fcbc68e3d0c7d03f44a4179a6c5071a

ObjectOwnership: 0x7f6d1fd3ce38654406b665dbeccc5c2494eb2458
ObjectOwnershipProxy: 0x0ce6fe3b598ece2b9cb026943ad3e2df41450481

InterstellarEncoder: 0x1481e177158dc074e64f536ddcb2416f55aa934b
```



