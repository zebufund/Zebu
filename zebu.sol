pragma solidity ^0.5.17;

interface Callable {
	function tokenCallback(address _from, uint256 _tokens, bytes calldata _data) external returns (bool);
}

//Zebu smart contract

contract Zebu{
    
//============= public variables ==============
    
    string constant public name = "Zebu";
    string constant public symbol = "ZBU";
    uint constant public decimals = 18;
    
//============= private functions ==============
    
    uint256 constant private START_SUPPLY = 8e25;
    uint256 constant private MINIMUM_SUPPLY_PERC = 9;
    uint256 constant private MIN_AMOUNT_STAKING = 1000;
    uint256 constant private FLUSHING_RATIO = 6;
    uint256 constant private DEFAULT_SCALAR_VALUE = 2**64;
    
    
//============= Events ==============
    
    event Staking(address indexed holder, uint256 amountCoins);
    event UnStaking(address indexed holder, uint256 amountCoins);
    event ColletRewards(address indexed holder, uint256 amountCoins);
    // Amount that will be flushed after a transfer to one address
    event Flush(uint256 amountCoins);
    event Transfer(address indexed sender, address indexed receiver, uint256 amountCoins);
    event Approval(address indexed holder, address indexed spender, uint256 tokens);
    event FlushingDisabled(address indexed user, bool status);


//============= structs ==============
    struct Holder {
        uint256 balance;
        uint256 amountStaked;
        mapping(address => uint256) allowance;
        int256 scaledPayout;
    }

    struct Data {
        address adminAddress;
        uint256 totalSupply;
        uint256 totalStaked;
        mapping(address => Holder) holders;
        uint256 scaledPayout;
    }

    Data private data;

//============= constructor ==============
    


    constructor() public{
        data.adminAddress = msg.sender;
        data.totalSupply = START_SUPPLY;
        data.holders[msg.sender].balance = START_SUPPLY;
        emit Transfer(address(0x0), msg.sender, START_SUPPLY);
    }
    
//============= private functions ==============
    
    
function _transfer(address _sender, address _receiver, uint256 _amountCoins) internal returns (uint256){
        require(balanceOf(_sender) >= _amountCoins);
        data.holders[_sender].balance -= _amountCoins;
        uint256 _amountFlushed = _amountCoins * FLUSHING_RATIO / 100;

        if(totalSupply() - _amountFlushed < START_SUPPLY * MINIMUM_SUPPLY_PERC / 100 ){
            _amountFlushed = 0;
        }

        uint256 _transferring = _amountCoins - _amountFlushed;
        data.holders[_receiver].balance += _transferring;

        emit Transfer(_sender, address(this), _amountCoins);
        if (_amountFlushed > 0) {
			if (data.totalStaked > 0) {
				_amountFlushed /= 2;
				data.scaledPayout += _amountFlushed * DEFAULT_SCALAR_VALUE / data.totalStaked;
				emit Transfer(_sender, address(this), _amountFlushed);
			}

			data.totalSupply -= _amountFlushed;
			emit Transfer(_sender, address(0x0), _amountFlushed);
			emit Flush(_amountFlushed);
		}

		return _transferring;

    }
    

function _staking(uint256 _amountCoins) internal {
        require(balanceOf(msg.sender) >= _amountCoins);
        require(getStaker(msg.sender) + _amountCoins >= MIN_AMOUNT_STAKING);
        data.totalStaked += _amountCoins;
        data.holders[msg.sender].amountStaked += _amountCoins;
        data.holders[msg.sender].scaledPayout += int256(_amountCoins * data.scaledPayout);
        emit Transfer(msg.sender, address(this), _amountCoins);
        emit Staking(msg.sender, _amountCoins);
    }

    function _unstaking(uint256 _amountCoins) internal {
		require(getStaker(msg.sender) >= _amountCoins);
		uint256 _amountFlushed = _amountCoins * FLUSHING_RATIO / 100;
		data.scaledPayout += _amountFlushed * DEFAULT_SCALAR_VALUE / data.totalStaked;
		data.totalStaked -= _amountCoins;
		data.holders[msg.sender].balance -= _amountFlushed;
		data.holders[msg.sender].amountStaked -= _amountCoins;
		data.holders[msg.sender].scaledPayout -= int256(_amountCoins * data.scaledPayout);
		emit Transfer(address(this), msg.sender, _amountCoins - _amountFlushed);
		emit UnStaking(msg.sender, _amountCoins);
	}

//============= get functions ==============    
    
     function balanceOf(address _holder) public view returns (uint256){
        return data.holders[_holder].balance - getStaker(_holder);
    }

    function getStaker(address _holder) public view returns (uint256){
        return data.holders[_holder].amountStaked;
    }
    
    function totalSupply() public view returns (uint256){
        return data.totalSupply;
    }

    function totalStaked() public view returns (uint256){
        return data.totalStaked;
    }
    
    function allowance(address _holder, address _spender) public view returns (uint256) {
		return data.holders[_holder].allowance[_spender];
	}

    function getRewards(address _holder) public view returns (uint256){
        return uint256(int256(data.scaledPayout * data.holders[_holder].amountStaked) - data.holders[_holder].scaledPayout) / DEFAULT_SCALAR_VALUE;
    }

    function getData(address _holder)public view returns (uint256 totalSupplyHolder, uint256 totalStakedHolder, uint256 balanceHolder, uint256 stakedHolder, uint256 rewardsHolder){
        return (totalSupply(), totalStaked(), balanceOf(_holder), getStaker(_holder), getRewards(_holder));
    }

//============= public functions ==============

    function flush(uint256 _coins) external {
        require(balanceOf(msg.sender) >= _coins);
        data.holders[msg.sender].balance -= _coins;
        uint256 _amountFlushed = _coins;
        if(data.totalStaked > 0){
            _amountFlushed /= 2;
            data.scaledPayout += _amountFlushed * DEFAULT_SCALAR_VALUE / data.totalStaked;
            emit Transfer(msg.sender, address(this), _amountFlushed);

        }

        data.totalSupply -= _amountFlushed;
        emit Transfer(msg.sender, address(0x0), _amountFlushed);
        emit Flush(_amountFlushed);
    }

    function staking(uint256 _amountCoins) external {
        _staking(_amountCoins);
    }

    function unstaking(uint256 _amountCoins) external {
		_unstaking(_amountCoins);
	}

    function approve(address _spender, uint256 _amountCoins) external returns (bool){
        data.holders[msg.sender].allowance[_spender] = _amountCoins;
        emit Approval(msg.sender, _spender, _amountCoins);
        return true;
    }

    

    function bulkTransfer(address[] calldata _receivers, uint256[] calldata _amountCoins) external{
        require(_receivers.length == _amountCoins.length);
        for (uint256 i = 0; i < _receivers.length; i++) {
			_transfer(msg.sender, _receivers[i], _amountCoins[i]);
		}
    }

    function transferFrom(address _sender, address _receiver, uint256 _amountCoins) external returns (bool) {
		require(data.holders[_sender].allowance[msg.sender] >= _amountCoins);
		data.holders[_sender].allowance[msg.sender] -= _amountCoins;
		_transfer(_sender, _receiver, _amountCoins);
		return true;
	}

	function transfer(address _receiver, uint256 _amountCoins) external returns (bool) {
		_transfer(msg.sender, _receiver, _amountCoins);
		return true;
	}

    function transferPlusReceiveData(address _receiver, uint256 _amountCoins, bytes calldata _data) external returns (bool){
        uint256 _transferring = _transfer(msg.sender, _receiver, _amountCoins);
        uint32 _size;
        assembly {
            _size := extcodesize(_receiver)
        }
        if(_size > 0){
            require(Callable(_receiver).tokenCallback(msg.sender, _transferring, _data));
        }
        return true;
    }

    function allocate(uint256 _amountCoins) external{
        require(data.totalStaked > 0);
        require(balanceOf(msg.sender) >= _amountCoins);
        data.holders[msg.sender].balance -= _amountCoins;
        data.scaledPayout += _amountCoins * DEFAULT_SCALAR_VALUE / data.totalStaked;
        emit Transfer(msg.sender,address(this), _amountCoins);
        
    }
    
    function collectRewards() external returns (uint256) {
		uint256 _holdersWhoCanClaimRewards = getRewards(msg.sender);
		require(_holdersWhoCanClaimRewards >= 0);
		data.holders[msg.sender].scaledPayout += int256(_holdersWhoCanClaimRewards * DEFAULT_SCALAR_VALUE);
		data.holders[msg.sender].balance += _holdersWhoCanClaimRewards;
		emit Transfer(address(this), msg.sender, _holdersWhoCanClaimRewards);
		emit ColletRewards(msg.sender, _holdersWhoCanClaimRewards);
		return _holdersWhoCanClaimRewards;
	}
    
 
   
}