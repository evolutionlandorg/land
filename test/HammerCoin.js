require('babel-register')({
    ignore: /node_modules\/(?!zeppelin-solidity)/
});
require('babel-polyfill');

import hammerCoin from '/Users/hammer/Downloads/itering/code/test/migrations/2_hammercoin.js';


console.log(hammerCoin.address);