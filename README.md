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



