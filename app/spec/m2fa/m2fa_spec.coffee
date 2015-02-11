describe "m2fa", ->
  beforeAll ->
    spyOn(_, 'defer')
    ledger.storage.sync = new ledger.storage.SyncedStore("synced_store", "private_key")
    ledger.storage.sync.client = jasmine.createSpyObj('restClient', ['get_settings_md5','get_settings','post_settings','put_settings','delete_settings'])

  beforeEach ->
    @$ = ledger.m2fa
    spyOn(@$, 'Client').and.returnValue jasmine.createSpyObj('client', ['on','off','sendChallenge','rejectPairing','confirmPairing','requestValidation'])

  it "init device pairing with a new random pairingId, a client, listen client event, and return the pairingId and a promise", ->
    pairingId = "a_random_pairing_id"
    spyOn(@$, '_nextPairingId').and.returnValue(pairingId)

    result = @$.pairDevice()

    expect(@$._nextPairingId).toHaveBeenCalled()
    client = @$.clients[pairingId]
    expect(client).toBeDefined()
    expect(@$.Client).toHaveBeenCalledWith(pairingId)
    
    expect(client.on.calls.count()).toBe(2)
    expect(client.on.calls.argsFor(0)[0]).toBe('m2fa.identify')
    expect(client.on.calls.argsFor(0)[1]).toEqual(jasmine.any(Function))
    expect(client.on.calls.argsFor(1)[0]).toBe('m2fa.challenge')
    expect(client.on.calls.argsFor(1)[1]).toEqual(jasmine.any(Function))

    expect(result).toEqual(jasmine.any(Array))
    expect(result.length).toBe(2)
    expect(result[0]).toBe(pairingId)
    expect(result[1].constructor.name).toBe('Promise')

  it "prefix pairingId when it save asociated label", ->
    spyOn(ledger.storage.sync, 'set')
    @$.setPairingLabel("a_random_pairing_id", "label")
    expect(ledger.storage.sync.set).toHaveBeenCalledWith("__m2fa_a_random_pairing_id": "label")

  it "remove pairingId prefix when it get all pairing labels", ->
    spyOn(ledger.storage.sync, 'keys').and.callFake (cb) -> cb(["__m2fa_a_random_pairing_id", 'onOtherBadKey'])
    spyOn(ledger.storage.sync, 'get').and.callFake (key, cb) -> cb("__m2fa_a_random_pairing_id": "label")

    result = @$.getPairingIds()
    expect(result.constructor.name).toBe('Promise')
    expect(ledger.storage.sync.get).toHaveBeenCalled()
    expect(ledger.storage.sync.get.calls.argsFor(0)[0]).toEqual(["__m2fa_a_random_pairing_id"])
    expect(result.valueOf()).toEqual("a_random_pairing_id": "label")

  it "get client corresponding to pairingId, clear previous listners, set new listeners and call requestValidation on validateTx", ->
    tx =
      _out: {authorizationPaired: "XxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXx"}
    pairingId = "a_random_pairing_id"
    client = jasmine.createSpyObj('client',['on','off','sendChallenge','rejectPairing','confirmPairing','requestValidation'])
    spyOn(@$, '_getClientFor').and.returnValue(client)
    
    r = @$.validateTx(tx, pairingId)

    expect(r.constructor.name).toBe('Promise')

    expect(@$._getClientFor).toHaveBeenCalledWith(pairingId)
    expect(client.off.calls.count()).toBe(2)
    expect(client.off.calls.argsFor(0)).toEqual(["m2fa.accept"])
    expect(client.off.calls.argsFor(1)).toEqual(["m2fa.response"])

    expect(client.on.calls.argsFor(0)[0]).toBe('m2fa.accept')
    expect(client.on.calls.argsFor(0)[1]).toEqual(jasmine.any(Function))
    expect(client.on.calls.argsFor(1)[0]).toBe('m2fa.response')
    expect(client.on.calls.argsFor(1)[1]).toEqual(jasmine.any(Function))
    expect(client.requestValidation).toHaveBeenCalledWith(tx._out.authorizationPaired)

  it "get call validateTx for each client on validateTxOnAll", ->
    tx =
      _out: {authorizationPaired: "XxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXx"}
    spyOn(@$, 'getPairingIds').and.returnValue(then: ((cb) -> cb("a_random_pairing_id":"label")))
    spyOn(@$, 'validateTx').and.returnValue(Q.defer().promise)
    r = @$.validateTxOnAll(tx)
    expect(@$.validateTx.calls.count()).toBe(1)
    expect(@$.validateTx.calls.argsFor(0)).toEqual([tx,"a_random_pairing_id"])

  it "_nextPairingId call _randomPairingId", ->
    spyOn(@$, '_randomPairingId')
    @$._nextPairingId()
    expect(@$._randomPairingId).toHaveBeenCalled()

  it "_randomPairingId return a 17 bytes hex encoded string", ->
    for i in [0...50]
      r = @$._randomPairingId()
      expect(r).toEqual(jasmine.any(String))
      expect(r).toMatch(/^[0-9a-fA-F]{34}$/)

  it "_getClientFor return client or create it if not present", ->
    @$.clients["9876"] = "saved_client"
    r = @$._getClientFor("9876")
    expect(r).toBe("saved_client")
    expect(@$.Client).not.toHaveBeenCalled()

    r = @$._getClientFor("0123")
    expect(@$.Client).toHaveBeenCalledWith("0123")
    expect(@$.clients["0123"]).toEqual(r)
